module Internal.Model exposing (..)

{-| -}

import Color exposing (Color)
import Html exposing (Html)
import Html.Attributes
import Internal.Style
import Json.Encode as Json
import Regex
import Set exposing (Set)
import VirtualCss
import VirtualDom


type Element msg
    = Unstyled (LayoutContext -> Html msg)
    | Styled
        { styles : List Style
        , html : Maybe String -> LayoutContext -> Html msg
        }
    | Text String
    | Empty


type LayoutContext
    = AsRow
    | AsColumn
    | AsEl
    | AsGrid
    | AsGridEl



{- Constants -}


asGrid : LayoutContext
asGrid =
    AsGrid


asRow : LayoutContext
asRow =
    AsRow


asColumn : LayoutContext
asColumn =
    AsColumn


asEl : LayoutContext
asEl =
    AsEl


asGridEl : LayoutContext
asGridEl =
    AsGridEl


type Aligned
    = Unaligned
    | Aligned (Maybe HAlign) (Maybe VAlign)


type HAlign
    = Left
    | CenterX
    | Right


type VAlign
    = Top
    | CenterY
    | Bottom


hover : Style -> Attribute msg
hover style =
    StyleClass (PseudoSelector Hover style)


type Style
    = Style String (List Property)
      --       class  prop   val
    | LineHeight Float
    | FontFamily String (List Font)
    | FontSize Int
    | Single String String String
    | Colored String String Color
    | SpacingStyle Int Int
    | PaddingStyle Int Int Int Int
    | GridTemplateStyle
        { spacing : ( Length, Length )
        , columns : List Length
        , rows : List Length
        }
    | GridPosition
        { row : Int
        , col : Int
        , width : Int
        , height : Int
        }
    | PseudoSelector PseudoClass Style


type PseudoClass
    = Focus
    | Hover


type Font
    = Serif
    | SansSerif
    | Monospace
    | Typeface String
    | ImportFont String String


type Property
    = Property String String


type Transformation
    = Move (Maybe Float) (Maybe Float) (Maybe Float)
    | Rotate Float Float Float Float
    | Scale Float Float Float


type Attribute msg
    = Attr (Html.Attribute msg)
    | Describe Description
      -- invalidation key and literal class
    | Class String String
      -- invalidation key "border-color" as opposed to "border-color-10-10-10" that will be the key for the class
    | StyleClass Style
      -- Descriptions will add aria attributes and if the element is not a link, may set the node type.
    | AlignY VAlign
    | AlignX HAlign
    | Width Length
    | Height Length
    | Nearby Location (Element msg)
    | Transform (Maybe PseudoClass) Transformation
      -- | Move (Maybe Float) (Maybe Float) (Maybe Float)
      -- | Rotate Float Float Float Float
      -- | Scale Float Float Float
    | TextShadow
        { offset : ( Float, Float )
        , blur : Float
        , color : Color
        }
    | BoxShadow
        { inset : Bool
        , offset : ( Float, Float )
        , size : Float
        , blur : Float
        , color : Color
        }
    | Filter FilterType
    | NoAttribute


type Description
    = Main
    | Navigation
      -- | Search
    | ContentInfo
    | Complementary
    | Heading Int
    | Label String
    | LivePolite
    | LiveAssertive
    | Button


type FilterType
    = FilterUrl String
    | Blur Float
    | Brightness Float
    | Contrast Float
    | Grayscale Float
    | HueRotate Float
    | Invert Float
    | OpacityFilter Float
    | Saturate Float
    | Sepia Float
    | DropShadow
        { offset : ( Float, Float )
        , size : Float
        , blur : Float
        , color : Color
        }


type Length
    = Px Int
    | Content
    | Fill Int


type Axis
    = XAxis
    | YAxis
    | AllAxis


type Location
    = Above
    | Below
    | OnRight
    | OnLeft
    | InFront
    | Behind


map : (msg -> msg1) -> Element msg -> Element msg1
map fn el =
    case el of
        Styled styled ->
            Styled
                { styles = styled.styles
                , html = \add context -> Html.map fn <| styled.html add context
                }

        Unstyled html ->
            Unstyled (Html.map fn << html)

        Text str ->
            Text str

        Empty ->
            Empty


mapAttr : (msg -> msg1) -> Attribute msg -> Attribute msg1
mapAttr fn attr =
    case attr of
        NoAttribute ->
            NoAttribute

        Describe description ->
            Describe description

        AlignX x ->
            AlignX x

        AlignY y ->
            AlignY y

        Width x ->
            Width x

        Height x ->
            Height x

        -- invalidation key "border-color" as opposed to "border-color-10-10-10" that will be the key for the class
        Class x y ->
            Class x y

        StyleClass style ->
            StyleClass style

        Nearby location element ->
            Nearby location (map fn element)

        Transform pseudo trans ->
            Transform pseudo trans

        Attr htmlAttr ->
            Attr (Html.Attributes.map fn htmlAttr)

        TextShadow shadow ->
            TextShadow shadow

        BoxShadow shadow ->
            BoxShadow shadow

        Filter filter ->
            Filter filter


class : String -> Attribute msg
class x =
    Class x x


{-| -}
embed : (a -> Element msg) -> a -> LayoutContext -> Html msg
embed fn a =
    case fn a of
        Unstyled html ->
            html

        Styled styled ->
            styled.html
                (Just
                    (toStyleSheetString
                        { hover = AllowHover
                        , focus =
                            { borderColor = Nothing
                            , shadow = Nothing
                            , backgroundColor = Nothing
                            }
                        }
                        styled.styles
                    )
                )

        Text text ->
            always (Html.text text)

        Empty ->
            always (Html.text "")


{-| -}
unstyled : Html msg -> Element msg
unstyled =
    Unstyled << always


{-| -}
renderNode : Aligned -> NodeName -> List (VirtualDom.Property msg) -> Children (VirtualDom.Node msg) -> Maybe String -> LayoutContext -> VirtualDom.Node msg
renderNode alignment node attrs children styles context =
    let
        createNode node attrs styles =
            case children of
                Keyed keyed ->
                    VirtualDom.keyedNode node
                        attrs
                        (case styles of
                            Nothing ->
                                keyed

                            Just stylesheet ->
                                ( "stylesheet-pls-pls-pls-be-unique"
                                , VirtualDom.node "style" [ Html.Attributes.class "stylesheet" ] [ Html.text stylesheet ]
                                )
                                    :: keyed
                        )

                Unkeyed unkeyed ->
                    VirtualDom.node node
                        attrs
                        (case styles of
                            Nothing ->
                                unkeyed

                            Just stylesheet ->
                                VirtualDom.node "style" [ Html.Attributes.class "stylesheet" ] [ Html.text stylesheet ] :: unkeyed
                        )

        html =
            case node of
                Generic ->
                    createNode "div" attrs styles

                NodeName nodeName ->
                    createNode nodeName attrs styles

                Embedded nodeName internal ->
                    VirtualDom.node nodeName
                        attrs
                        [ createNode internal [ Html.Attributes.class "se el" ] styles
                        ]
    in
    case context of
        AsEl ->
            html

        AsGrid ->
            html

        AsGridEl ->
            html

        AsRow ->
            case alignment of
                Unaligned ->
                    html

                Aligned (Just Left) _ ->
                    VirtualDom.node "alignLeft"
                        [ Html.Attributes.class "se el container align-container-left content-center-y" ]
                        [ html ]

                Aligned (Just Right) _ ->
                    VirtualDom.node "alignRight"
                        [ Html.Attributes.class "se el container align-container-right content-center-y" ]
                        [ html ]

                _ ->
                    html

        AsColumn ->
            case alignment of
                Unaligned ->
                    VirtualDom.node "alignTop"
                        [ Html.Attributes.class "se el container align-container-top" ]
                        [ html ]

                Aligned _ Nothing ->
                    VirtualDom.node "alignTop"
                        [ Html.Attributes.class "se el container align-container-top" ]
                        [ html ]

                Aligned _ (Just Top) ->
                    VirtualDom.node "alignTop"
                        [ Html.Attributes.class "se el container align-container-top" ]
                        [ html ]

                Aligned _ (Just Bottom) ->
                    VirtualDom.node "alignBottom"
                        [ Html.Attributes.class "se el container align-container-bottom" ]
                        [ html ]

                _ ->
                    html


renderKeyedNode : Aligned -> NodeName -> List (VirtualDom.Property msg) -> List ( String, VirtualDom.Node msg ) -> Maybe String -> LayoutContext -> VirtualDom.Node msg
renderKeyedNode alignment node attrs children styles context =
    let
        html =
            case node of
                Generic ->
                    VirtualDom.keyedNode "div"
                        attrs
                        (case styles of
                            Nothing ->
                                children

                            Just stylesheet ->
                                ( "stylesheet-pls-pls-pls-be-unique"
                                , VirtualDom.node "style" [ Html.Attributes.class "stylesheet" ] [ Html.text stylesheet ]
                                )
                                    :: children
                        )

                NodeName nodeName ->
                    VirtualDom.keyedNode nodeName
                        attrs
                        (case styles of
                            Nothing ->
                                children

                            Just stylesheet ->
                                ( "stylesheet-pls-pls-pls-be-unique"
                                , VirtualDom.node "style" [ Html.Attributes.class "stylesheet" ] [ Html.text stylesheet ]
                                )
                                    :: children
                        )

                Embedded nodeName internal ->
                    VirtualDom.node nodeName
                        attrs
                        [ VirtualDom.keyedNode internal
                            [ Html.Attributes.class "se el" ]
                            (case styles of
                                Nothing ->
                                    children

                                Just stylesheet ->
                                    ( "stylesheet-pls-pls-pls-be-unique"
                                    , VirtualDom.node "style" [ Html.Attributes.class "stylesheet" ] [ Html.text stylesheet ]
                                    )
                                        :: children
                            )
                        ]
    in
    case context of
        AsEl ->
            html

        AsGridEl ->
            html

        AsGrid ->
            html

        AsRow ->
            case alignment of
                Unaligned ->
                    html

                Aligned (Just Left) _ ->
                    VirtualDom.node "alignLeft"
                        [ Html.Attributes.class "se el container align-container-left" ]
                        [ html ]

                Aligned (Just Right) _ ->
                    VirtualDom.node "alignRight"
                        [ Html.Attributes.class "se el container align-container-right" ]
                        [ html ]

                _ ->
                    html

        AsColumn ->
            case alignment of
                Unaligned ->
                    html

                Aligned _ (Just Top) ->
                    VirtualDom.node "alignTop"
                        [ Html.Attributes.class "se el container align-container-top" ]
                        [ html ]

                Aligned _ (Just Bottom) ->
                    VirtualDom.node "alignBottom"
                        [ Html.Attributes.class "se el container align-container-bottom" ]
                        [ html ]

                _ ->
                    html


addNodeName : String -> NodeName -> NodeName
addNodeName newNode old =
    case old of
        Generic ->
            NodeName newNode

        NodeName name ->
            Embedded name newNode

        Embedded x y ->
            Embedded x y


alignXName : HAlign -> String
alignXName align =
    case align of
        Left ->
            "self-left"

        Right ->
            "self-right"

        CenterX ->
            "self-center-x"


alignYName : VAlign -> String
alignYName align =
    case align of
        Top ->
            "self-top"

        Bottom ->
            "self-bottom"

        CenterY ->
            "self-center-y"


gatherAttributes : Attribute msg -> Gathered msg -> Gathered msg
gatherAttributes =
    gatherAttributesWith Gather


type GatherMode msg
    = Gather
    | GatherPseudo
        { pseudoClass : PseudoClass
        , additionalAttributes : List (Html.Attribute msg)
        }


gatherAttributesWith : GatherMode msg -> Attribute msg -> Gathered msg -> Gathered msg
gatherAttributesWith mode attr gathered =
    let
        className name =
            case mode of
                Gather ->
                    VirtualDom.property "className" (Json.string name)

                GatherPseudo { pseudoClass } ->
                    let
                        baseName =
                            psuedoClassName pseudoClass ++ "-" ++ name
                    in
                    VirtualDom.property "className" (Json.string baseName)

        styleName name =
            case mode of
                Gather ->
                    "." ++ name

                GatherPseudo { pseudoClass } ->
                    "." ++ psuedoClassName pseudoClass ++ "-" ++ name

        formatStyleClass style =
            case style of
                PseudoSelector selector style ->
                    PseudoSelector selector (formatStyleClass style)

                Style class props ->
                    Style (styleName class) props

                Single class name val ->
                    Single (styleName class) name val

                Colored class name val ->
                    Colored (styleName class) name val

                SpacingStyle x y ->
                    SpacingStyle x y

                PaddingStyle top right bottom left ->
                    PaddingStyle top right bottom left

                GridTemplateStyle grid ->
                    GridTemplateStyle grid

                GridPosition pos ->
                    GridPosition pos

                LineHeight i ->
                    LineHeight i

                FontFamily name fam ->
                    FontFamily name fam

                FontSize i ->
                    FontSize i
    in
    case attr of
        NoAttribute ->
            gathered

        Class key class ->
            if Set.member key gathered.has then
                gathered
            else
                { gathered
                    | attributes = className class :: gathered.attributes
                    , has = Set.insert key gathered.has
                }

        Attr attr ->
            case mode of
                Gather ->
                    { gathered | attributes = attr :: gathered.attributes }

                GatherPseudo _ ->
                    gathered

        StyleClass style ->
            let
                key =
                    styleKey style
            in
            if Set.member key gathered.has then
                gathered
            else
                { gathered
                    | attributes =
                        case style of
                            PseudoSelector Hover _ ->
                                VirtualDom.property "className" (Json.string "hover-transition") :: className (getStyleName style) :: gathered.attributes

                            _ ->
                                className (getStyleName style) :: gathered.attributes
                    , styles = formatStyleClass style :: gathered.styles
                    , has = Set.insert key gathered.has
                }

        Width width ->
            if gathered.width == Nothing then
                case width of
                    Px px ->
                        { gathered
                            | width = Just width
                            , attributes = className ("width-exact width-px-" ++ toString px) :: gathered.attributes
                            , styles = Single (styleName <| "width-px-" ++ toString px) "width" (toString px ++ "px") :: gathered.styles
                        }

                    Content ->
                        { gathered
                            | width = Just width
                            , attributes = className "width-content" :: gathered.attributes
                        }

                    Fill portion ->
                        if portion == 1 then
                            { gathered
                                | width = Just width
                                , attributes = className "width-fill" :: gathered.attributes
                            }
                        else
                            { gathered
                                | width = Just width
                                , attributes = className ("width-fill-portion width-fill-" ++ toString portion) :: gathered.attributes
                                , styles =
                                    Single (".se.row > " ++ (styleName <| "width-fill-" ++ toString portion)) "flex-grow" (toString (portion * 100000)) :: gathered.styles
                            }
            else
                gathered

        Height height ->
            if gathered.height == Nothing then
                case height of
                    Px px ->
                        { gathered
                            | height = Just height
                            , attributes = className ("height-px-" ++ toString px) :: gathered.attributes
                            , styles = Single (styleName <| "height-px-" ++ toString px) "height" (toString px ++ "px") :: gathered.styles
                        }

                    Content ->
                        { gathered
                            | height = Just height
                            , attributes = className "height-content" :: gathered.attributes
                        }

                    Fill portion ->
                        if portion == 1 then
                            { gathered
                                | height = Just height
                                , attributes = className "height-fill" :: gathered.attributes
                            }
                        else
                            { gathered
                                | height = Just height
                                , attributes = className ("height-fill-portion height-fill-" ++ toString portion) :: gathered.attributes
                                , styles =
                                    Single (".se.column > " ++ (styleName <| "height-fill-" ++ toString portion)) "flex-grow" (toString (portion * 100000)) :: gathered.styles
                            }
            else
                gathered

        Describe description ->
            case mode of
                GatherPseudo _ ->
                    gathered

                Gather ->
                    case description of
                        Main ->
                            { gathered | node = addNodeName "main" gathered.node }

                        Navigation ->
                            { gathered | node = addNodeName "nav" gathered.node }

                        ContentInfo ->
                            { gathered | node = addNodeName "footer" gathered.node }

                        Complementary ->
                            { gathered | node = addNodeName "aside" gathered.node }

                        Heading i ->
                            if i <= 1 then
                                { gathered | node = addNodeName "h1" gathered.node }
                            else if i < 7 then
                                { gathered | node = addNodeName ("h" ++ toString i) gathered.node }
                            else
                                { gathered | node = addNodeName "h6" gathered.node }

                        Button ->
                            { gathered | attributes = Html.Attributes.attribute "aria-role" "button" :: gathered.attributes }

                        Label label ->
                            { gathered | attributes = Html.Attributes.attribute "aria-label" label :: gathered.attributes }

                        LivePolite ->
                            { gathered | attributes = Html.Attributes.attribute "aria-live" "polite" :: gathered.attributes }

                        LiveAssertive ->
                            { gathered | attributes = Html.Attributes.attribute "aria-live" "assertive" :: gathered.attributes }

        Nearby location elem ->
            let
                nearbyGroup =
                    case gathered.nearbys of
                        Nothing ->
                            { above = Nothing
                            , below = Nothing
                            , right = Nothing
                            , left = Nothing
                            , infront = Nothing
                            , behind = Nothing
                            }

                        Just x ->
                            x

                styles =
                    case elem of
                        Empty ->
                            Nothing

                        Text str ->
                            Nothing

                        Unstyled html ->
                            Nothing

                        Styled styled ->
                            Just <| gathered.styles ++ styled.styles

                addIfEmpty existing =
                    case existing of
                        Nothing ->
                            case elem of
                                Empty ->
                                    Nothing

                                Text str ->
                                    Just (textElement str)

                                Unstyled html ->
                                    Just (html asEl)

                                Styled styled ->
                                    Just (styled.html Nothing asEl)

                        _ ->
                            existing
            in
            { gathered
                | styles =
                    case styles of
                        Nothing ->
                            gathered.styles

                        Just newStyles ->
                            newStyles
                , nearbys =
                    Just <|
                        case location of
                            Above ->
                                { nearbyGroup
                                    | above = addIfEmpty nearbyGroup.above
                                }

                            Below ->
                                { nearbyGroup
                                    | below = addIfEmpty nearbyGroup.below
                                }

                            OnRight ->
                                { nearbyGroup
                                    | right = addIfEmpty nearbyGroup.right
                                }

                            OnLeft ->
                                { nearbyGroup
                                    | left = addIfEmpty nearbyGroup.left
                                }

                            InFront ->
                                { nearbyGroup
                                    | infront = addIfEmpty nearbyGroup.infront
                                }

                            Behind ->
                                { nearbyGroup
                                    | behind = addIfEmpty nearbyGroup.behind
                                }
            }

        AlignX x ->
            case gathered.alignment of
                Unaligned ->
                    { gathered
                        | attributes = className (alignXName x) :: gathered.attributes
                        , alignment = Aligned (Just x) Nothing
                    }

                Aligned (Just _) _ ->
                    gathered

                Aligned _ y ->
                    { gathered
                        | attributes = className (alignXName x) :: gathered.attributes
                        , alignment = Aligned (Just x) y
                    }

        AlignY y ->
            case gathered.alignment of
                Unaligned ->
                    { gathered
                        | attributes = className (alignYName y) :: gathered.attributes
                        , alignment = Aligned Nothing (Just y)
                    }

                Aligned _ (Just _) ->
                    gathered

                Aligned x _ ->
                    { gathered
                        | attributes = className (alignYName y) :: gathered.attributes
                        , alignment = Aligned x (Just y)
                    }

        Filter filter ->
            case gathered.filters of
                Nothing ->
                    { gathered | filters = Just (filterName filter) }

                Just existing ->
                    { gathered | filters = Just (filterName filter ++ " " ++ existing) }

        BoxShadow shadow ->
            case gathered.boxShadows of
                Nothing ->
                    { gathered | boxShadows = Just (formatBoxShadow shadow) }

                Just existing ->
                    { gathered | boxShadows = Just (formatBoxShadow shadow ++ ", " ++ existing) }

        TextShadow shadow ->
            case gathered.textShadows of
                Nothing ->
                    { gathered | textShadows = Just (formatTextShadow shadow) }

                Just existing ->
                    { gathered | textShadows = Just (formatTextShadow shadow ++ ", " ++ existing) }

        Transform pseudoClass transform ->
            case transform of
                Move mx my mz ->
                    case pseudoClass of
                        Nothing ->
                            case gathered.transform of
                                Nothing ->
                                    { gathered
                                        | transform =
                                            Just
                                                { translate =
                                                    Just ( mx, my, mz )
                                                , scale = Nothing
                                                , rotate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transform = Just (addTranslate mx my mz transformation)
                                    }

                        Just Hover ->
                            case gathered.transformHover of
                                Nothing ->
                                    { gathered
                                        | transformHover =
                                            Just
                                                { translate =
                                                    Just ( mx, my, mz )
                                                , scale = Nothing
                                                , rotate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transformHover = Just (addTranslate mx my mz transformation)
                                    }

                        Just Focus ->
                            gathered

                Rotate x y z angle ->
                    case pseudoClass of
                        Nothing ->
                            case gathered.transform of
                                Nothing ->
                                    { gathered
                                        | transform =
                                            Just
                                                { rotate =
                                                    Just ( x, y, z, angle )
                                                , scale = Nothing
                                                , translate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transform = Just (addRotate x y z angle transformation)
                                    }

                        Just Hover ->
                            case gathered.transformHover of
                                Nothing ->
                                    { gathered
                                        | transformHover =
                                            Just
                                                { rotate =
                                                    Just ( x, y, z, angle )
                                                , scale = Nothing
                                                , translate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transformHover = Just (addRotate x y z angle transformation)
                                    }

                        Just Focus ->
                            gathered

                Scale x y z ->
                    case pseudoClass of
                        Nothing ->
                            case gathered.transform of
                                Nothing ->
                                    { gathered
                                        | transform =
                                            Just
                                                { scale =
                                                    Just ( x, y, z )
                                                , rotate = Nothing
                                                , translate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transform = Just (addScale x y z transformation)
                                    }

                        Just Hover ->
                            case gathered.transformHover of
                                Nothing ->
                                    { gathered
                                        | transformHover =
                                            Just
                                                { scale =
                                                    Just ( x, y, z )
                                                , rotate = Nothing
                                                , translate = Nothing
                                                }
                                    }

                                Just transformation ->
                                    { gathered
                                        | transformHover = Just (addScale x y z transformation)
                                    }

                        Just Focus ->
                            gathered



-- case gathered.rotation of
--     Nothing ->
--         { gathered
--             | rotation =
--                 Just
--                     ("rotate3d(" ++ toString x ++ "," ++ toString y ++ "," ++ toString z ++ "," ++ toString angle ++ "rad)")
--         }
--     _ ->
--         gathered
-- let
--     newScale =
--         case gathered.scale of
--             Nothing ->
--                 Just
--                     ( x
--                     , y
--                     , z
--                     )
--             _ ->
--                 gathered.scale
-- in
-- { gathered | scale = newScale }


type alias TransformationAlias a =
    { a
        | rotate : Maybe ( Float, Float, Float, Float )
        , translate : Maybe ( Maybe Float, Maybe Float, Maybe Float )
        , scale : Maybe ( Float, Float, Float )
    }


addScale x y z transformation =
    case transformation.scale of
        Nothing ->
            { transformation
                | scale =
                    Just ( x, y, z )
            }

        _ ->
            transformation


addRotate x y z angle transformation =
    case transformation.rotate of
        Nothing ->
            { transformation
                | rotate =
                    Just ( x, y, z, angle )
            }

        _ ->
            transformation


addTranslate : Maybe a -> Maybe a1 -> Maybe a2 -> { b | translate : Maybe ( Maybe a, Maybe a1, Maybe a2 ) } -> { b | translate : Maybe ( Maybe a, Maybe a1, Maybe a2 ) }
addTranslate mx my mz transformation =
    case transformation.translate of
        Nothing ->
            { transformation
                | translate =
                    Just ( mx, my, mz )
            }

        Just ( existingX, existingY, existingZ ) ->
            let
                addIfNothing val existing =
                    case existing of
                        Nothing ->
                            val

                        x ->
                            x
            in
            { transformation
                | translate =
                    Just
                        ( addIfNothing mx existingX
                        , addIfNothing my existingY
                        , addIfNothing mz existingZ
                        )
            }


type NodeName
    = Generic
    | NodeName String
    | Embedded String String


type alias NearbyGroup msg =
    { above : Maybe (Html msg)
    , below : Maybe (Html msg)
    , right : Maybe (Html msg)
    , left : Maybe (Html msg)
    , infront : Maybe (Html msg)
    , behind : Maybe (Html msg)
    }


type alias Gathered msg =
    { attributes : List (Html.Attribute msg)
    , styles : List Style
    , alignment : Aligned
    , width : Maybe Length
    , height : Maybe Length
    , nearbys : Maybe (NearbyGroup msg)
    , node : NodeName
    , filters : Maybe String
    , boxShadows : Maybe String
    , textShadows : Maybe String
    , transform : Maybe TransformationGroup
    , transformHover : Maybe TransformationGroup
    , has : Set String
    }


type alias TransformationGroup =
    { rotate : Maybe ( Float, Float, Float, Float )
    , translate : Maybe ( Maybe Float, Maybe Float, Maybe Float )
    , scale : Maybe ( Float, Float, Float )
    }


{-| Because of how it's constructed, we know that NearbyGroup is nonempty
-}
renderNearbyGroupAbsolute : NearbyGroup msg -> Html msg
renderNearbyGroupAbsolute nearby =
    let
        create ( location, node ) =
            case node of
                Nothing ->
                    Nothing

                Just el ->
                    Just <|
                        Html.div [ Html.Attributes.class (locationClass location) ] [ el ]
    in
    Html.div [ Html.Attributes.class "se el nearby" ]
        (List.filterMap create
            [ ( Above, nearby.above )
            , ( Below, nearby.below )
            , ( OnLeft, nearby.left )
            , ( OnRight, nearby.right )
            , ( InFront, nearby.infront )
            , ( Behind, nearby.behind )
            ]
        )


initGathered : Maybe String -> List Style -> Gathered msg
initGathered maybeNodeName styles =
    { attributes = []
    , styles = styles
    , width = Nothing
    , height = Nothing
    , alignment = Unaligned
    , node =
        case maybeNodeName of
            Nothing ->
                Generic

            Just name ->
                NodeName name
    , nearbys = Nothing
    , transform = Nothing
    , transformHover = Nothing
    , filters = Nothing
    , boxShadows = Nothing
    , textShadows = Nothing
    , has = Set.empty
    }


{-| -}
uncapitalize : String -> String
uncapitalize str =
    let
        head =
            String.left 1 str
                |> String.toLower

        tail =
            String.dropLeft 1 str
    in
    head ++ tail


{-| -}
className : String -> String
className x =
    x
        |> uncapitalize
        |> Regex.replace Regex.All (Regex.regex "[^a-zA-Z0-9_-]") (\_ -> "")
        |> Regex.replace Regex.All (Regex.regex "[A-Z0-9]+") (\{ match } -> " " ++ String.toLower match)
        |> Regex.replace Regex.All (Regex.regex "[\\s+]") (\_ -> "")



-- renderTransformationGroup : TransformationGroup -> Maybe String


renderTransformationGroup maybePostfix group =
    let
        translate =
            flip Maybe.map
                group.translate
                (\( x, y, z ) ->
                    "translate3d("
                        ++ toString (Maybe.withDefault 0 x)
                        ++ "px, "
                        ++ toString (Maybe.withDefault 0 y)
                        ++ "px, "
                        ++ toString (Maybe.withDefault 0 z)
                        ++ "px)"
                )

        scale =
            flip Maybe.map
                group.scale
                (\( x, y, z ) ->
                    "scale3d(" ++ toString x ++ ", " ++ toString y ++ ", " ++ toString z ++ ")"
                )

        rotate =
            flip Maybe.map
                group.rotate
                (\( x, y, z, angle ) ->
                    "rotate3d(" ++ toString x ++ "," ++ toString y ++ "," ++ toString z ++ "," ++ toString angle ++ "rad)"
                )

        transformations =
            List.filterMap identity
                [ scale
                , translate
                , rotate
                ]

        name =
            String.join "-" <|
                List.filterMap identity
                    [ flip Maybe.map
                        group.translate
                        (\( x, y, z ) ->
                            "move-"
                                ++ floatClass (Maybe.withDefault 0 x)
                                ++ "-"
                                ++ floatClass (Maybe.withDefault 0 y)
                                ++ "-"
                                ++ floatClass (Maybe.withDefault 0 z)
                        )
                    , flip Maybe.map
                        group.scale
                        (\( x, y, z ) ->
                            "scale" ++ floatClass x ++ "-" ++ floatClass y ++ "-" ++ floatClass z
                        )
                    , flip Maybe.map
                        group.rotate
                        (\( x, y, z, angle ) ->
                            "rotate-" ++ floatClass x ++ "-" ++ floatClass y ++ "-" ++ floatClass z ++ "-" ++ floatClass angle
                        )
                    ]
    in
    case transformations of
        [] ->
            Nothing

        trans ->
            let
                transforms =
                    String.join " " trans

                ( classOnElement, classInStylesheet ) =
                    case maybePostfix of
                        Nothing ->
                            ( "transform-" ++ name
                            , ".transform-" ++ name
                            )

                        Just ( postfix, pseudostate ) ->
                            ( "transform-" ++ name ++ "-" ++ postfix
                            , "." ++ "transform-" ++ name ++ "-" ++ postfix ++ ":" ++ pseudostate
                            )
            in
            Just ( classOnElement, Single classInStylesheet "transform" transforms )


formatTransformations : Gathered msg -> Gathered msg
formatTransformations gathered =
    let
        addTransform ( classes, styles ) =
            case gathered.transform of
                Nothing ->
                    ( classes, styles )

                Just transform ->
                    case renderTransformationGroup Nothing transform of
                        Nothing ->
                            ( classes, styles )

                        Just ( name, transformStyle ) ->
                            ( name :: classes
                            , transformStyle :: styles
                            )

        addHoverTransform ( classes, styles ) =
            case gathered.transformHover of
                Nothing ->
                    ( classes, styles )

                Just transform ->
                    case renderTransformationGroup (Just ( "hover", "hover" )) transform of
                        Nothing ->
                            ( classes, styles )

                        Just ( name, transformStyle ) ->
                            ( name :: classes
                            , transformStyle :: styles
                            )

        addFilters ( classes, styles ) =
            case gathered.filters of
                Nothing ->
                    ( classes, styles )

                Just filter ->
                    let
                        name =
                            "filter-" ++ className filter
                    in
                    ( name :: classes
                    , Single ("." ++ name) "filter" filter
                        :: styles
                    )

        addBoxShadows ( classes, styles ) =
            case gathered.boxShadows of
                Nothing ->
                    ( classes, styles )

                Just shades ->
                    let
                        name =
                            "box-shadow-" ++ className shades
                    in
                    ( name :: classes
                    , Single ("." ++ name) "box-shadow" shades
                        :: styles
                    )

        addTextShadows ( classes, styles ) =
            case gathered.textShadows of
                Nothing ->
                    ( classes, styles )

                Just shades ->
                    let
                        name =
                            "text-shadow-" ++ className shades
                    in
                    ( name :: classes
                    , Single ("." ++ name) "text-shadow" shades
                        :: styles
                    )
    in
    let
        ( classes, styles ) =
            ( [], gathered.styles )
                |> addFilters
                |> addBoxShadows
                |> addTextShadows
                |> addTransform
                |> addHoverTransform
    in
    { gathered
        | styles = styles
        , attributes =
            Html.Attributes.class (String.join " " classes) :: gathered.attributes
    }


renderAttributes : Maybe String -> List Style -> List (Attribute msg) -> Gathered msg
renderAttributes node styles attributes =
    case attributes of
        [] ->
            initGathered node styles

        attrs ->
            List.foldr gatherAttributes (initGathered node styles) attrs
                |> formatTransformations


rowEdgeFillers : List (Element msg) -> List (Element msg)
rowEdgeFillers children =
    unstyled
        (VirtualDom.node "alignLeft"
            [ Html.Attributes.class "se container align-container-left content-center-y spacer" ]
            []
        )
        :: children
        ++ [ unstyled
                (VirtualDom.node "alignRight"
                    [ Html.Attributes.class "se container align-container-right content-center-y spacer" ]
                    []
                )
           ]


keyedRowEdgeFillers : List ( String, Element msg ) -> List ( String, Element msg )
keyedRowEdgeFillers children =
    ( "left-filler-node-pls-pls-pls-be-unique"
    , unstyled
        (VirtualDom.node "alignLeft"
            [ Html.Attributes.class "se container align-container-left content-center-y spacer" ]
            []
        )
    )
        :: children
        ++ [ ( "right-filler-node-pls-pls-pls-be-unique"
             , unstyled
                (VirtualDom.node "alignRight"
                    [ Html.Attributes.class "se container align-container-right content-center-y spacer" ]
                    []
                )
             )
           ]


columnEdgeFillers : List (Element msg) -> List (Element msg)
columnEdgeFillers children =
    -- unstyled <|
    -- (VirtualDom.node "alignTop"
    --     [ Html.Attributes.class "se container align-container-top spacer" ]
    --     []
    -- ) ::
    children
        ++ [ unstyled
                (VirtualDom.node "div"
                    [ Html.Attributes.class "se container align-container-top teleporting-spacer" ]
                    []
                )
           , unstyled
                (VirtualDom.node "alignBottom"
                    [ Html.Attributes.class "se container align-container-bottom spacer" ]
                    []
                )
           ]


keyedColumnEdgeFillers : List ( String, Element msg ) -> List ( String, Element msg )
keyedColumnEdgeFillers children =
    -- unstyled <|
    -- (VirtualDom.node "alignTop"
    --     [ Html.Attributes.class "se container align-container-top spacer" ]
    --     []
    -- ) ::
    children
        ++ [ ( "teleporting-top-filler-node-pls-pls-pls-be-unique"
             , unstyled
                (VirtualDom.node "div"
                    [ Html.Attributes.class "se container align-container-top teleporting-spacer" ]
                    []
                )
             )
           , ( "bottom-filler-node-pls-pls-pls-be-unique"
             , unstyled
                (VirtualDom.node "alignBottom"
                    [ Html.Attributes.class "se container align-container-bottom spacer" ]
                    []
                )
             )
           ]


{-| TODO:

This doesn't reduce equivalent attributes completely.

-}
filter : List (Attribute msg) -> List (Attribute msg)
filter attrs =
    Tuple.first <|
        List.foldr
            (\x ( found, has ) ->
                case x of
                    NoAttribute ->
                        ( found, has )

                    Class key class ->
                        ( x :: found, has )

                    Attr attr ->
                        ( x :: found, has )

                    StyleClass style ->
                        ( x :: found, has )

                    Width width ->
                        if Set.member "width" has then
                            ( found, has )
                        else
                            ( x :: found, Set.insert "width" has )

                    Height height ->
                        if Set.member "height" has then
                            ( found, has )
                        else
                            ( x :: found, Set.insert "height" has )

                    Describe description ->
                        if Set.member "described" has then
                            ( found, has )
                        else
                            ( x :: found, Set.insert "described" has )

                    Nearby location elem ->
                        ( x :: found, has )

                    AlignX _ ->
                        if Set.member "align-x" has then
                            ( found, has )
                        else
                            ( x :: found, Set.insert "align-x" has )

                    AlignY _ ->
                        if Set.member "align-y" has then
                            ( found, has )
                        else
                            ( x :: found, Set.insert "align-y" has )

                    Filter filter ->
                        ( x :: found, has )

                    BoxShadow shadow ->
                        ( x :: found, has )

                    TextShadow shadow ->
                        ( x :: found, has )

                    Transform _ _ ->
                        ( x :: found, has )
            )
            ( [], Set.empty )
            attrs


get : List (Attribute msg) -> (Attribute msg -> Bool) -> List (Attribute msg)
get attrs isAttr =
    attrs
        |> filter
        |> List.foldr
            (\x found ->
                if isAttr x then
                    x :: found
                else
                    found
            )
            []


getSpacing : List (Attribute msg) -> ( Int, Int ) -> ( Int, Int )
getSpacing attrs default =
    attrs
        |> List.foldr
            (\x acc ->
                case acc of
                    Just x ->
                        Just x

                    Nothing ->
                        case x of
                            StyleClass (SpacingStyle x y) ->
                                Just ( x, y )

                            _ ->
                                Nothing
            )
            Nothing
        |> Maybe.withDefault default


getSpacingAttribute : List (Attribute msg) -> ( Int, Int ) -> Attribute msg1
getSpacingAttribute attrs default =
    attrs
        |> List.foldr
            (\x acc ->
                case acc of
                    Just x ->
                        Just x

                    Nothing ->
                        case x of
                            StyleClass (SpacingStyle x y) ->
                                Just ( x, y )

                            _ ->
                                Nothing
            )
            Nothing
        |> Maybe.withDefault default
        |> (\( x, y ) -> StyleClass (SpacingStyle x y))


row : List (Attribute msg) -> Children (Element msg) -> Element msg
row attrs children =
    element asRow Nothing (htmlClass "se row" :: attrs) children


column : List (Attribute msg) -> Children (Element msg) -> Element msg
column attrs children =
    element asColumn Nothing (htmlClass "se column" :: attrs) children


el : Maybe String -> List (Attribute msg) -> Element msg -> Element msg
el node attrs child =
    element asEl node (htmlClass "se el" :: attrs) (Unkeyed [ child ])


gridEl : Maybe String -> List (Attribute msg) -> List (Element msg) -> Element msg
gridEl node attrs children =
    element asGridEl node (htmlClass "se el" :: attrs) (Unkeyed children)


paragraph : List (Attribute msg) -> Children (Element msg) -> Element msg
paragraph attrs children =
    element asEl (Just "p") (htmlClass "se paragraph" :: attrs) children


textPage : List (Attribute msg) -> Children (Element msg) -> Element msg
textPage attrs children =
    element asEl Nothing (htmlClass "se page" :: attrs) children


textElement : String -> VirtualDom.Node msg
textElement str =
    VirtualDom.node "div"
        [ VirtualDom.property "className"
            (Json.string "se text width-content height-content")
        ]
        [ VirtualDom.text str ]


textElementFill : String -> VirtualDom.Node msg
textElementFill str =
    VirtualDom.node "div"
        [ VirtualDom.property "className"
            (Json.string "se text width-fill height-fill")
        ]
        [ VirtualDom.text str ]


type Children x
    = Unkeyed (List x)
    | Keyed (List ( String, x ))


element : LayoutContext -> Maybe String -> List (Attribute msg) -> Children (Element msg) -> Element msg
element context nodeName attributes children =
    let
        rendered =
            renderAttributes nodeName [] attributes

        ( htmlChildren, styleChildren ) =
            case children of
                Keyed keyedChildren ->
                    List.foldr gatherKeyed ( [], rendered.styles ) keyedChildren
                        |> Tuple.mapFirst Keyed

                Unkeyed unkeyedChildren ->
                    List.foldr gather ( [], rendered.styles ) unkeyedChildren
                        |> Tuple.mapFirst Unkeyed

        gather child ( htmls, existingStyles ) =
            case child of
                Unstyled html ->
                    ( html context :: htmls
                    , existingStyles
                    )

                Styled styled ->
                    ( styled.html Nothing context :: htmls
                    , styled.styles ++ existingStyles
                    )

                Text str ->
                    -- TEXT OPTIMIZATION
                    -- You can have raw text if the element is an el, and has `width-content` and `height-content`
                    -- Same if it's a column or row with one child and width-content, height-content
                    if rendered.width == Just Content && rendered.height == Just Content && context == asEl then
                        ( Html.text str
                            :: htmls
                        , existingStyles
                        )
                    else if context == asEl then
                        ( textElementFill str
                            :: htmls
                        , existingStyles
                        )
                    else
                        ( textElement str
                            :: htmls
                        , existingStyles
                        )

                Empty ->
                    ( htmls, existingStyles )

        gatherKeyed ( key, child ) ( htmls, existingStyles ) =
            case child of
                Unstyled html ->
                    ( ( key, html context ) :: htmls
                    , existingStyles
                    )

                Styled styled ->
                    ( ( key, styled.html Nothing context ) :: htmls
                    , styled.styles ++ existingStyles
                    )

                Text str ->
                    -- TEXT OPTIMIZATION
                    -- You can have raw text if the element is an el, and has `width-content` and `height-content`
                    -- Same if it's a column or row with one child and width-content, height-content
                    if rendered.width == Just Content && rendered.height == Just Content && context == asEl then
                        ( ( key, Html.text str )
                            :: htmls
                        , existingStyles
                        )
                    else
                        ( ( key, textElement str )
                            :: htmls
                        , existingStyles
                        )

                Empty ->
                    ( htmls, existingStyles )

        renderedChildren =
            case Maybe.map renderNearbyGroupAbsolute rendered.nearbys of
                Nothing ->
                    htmlChildren

                Just nearby ->
                    case htmlChildren of
                        Keyed keyed ->
                            Keyed <| ( "nearby-elements-pls-pls-pls-pls-be-unique", nearby ) :: keyed

                        Unkeyed unkeyed ->
                            Unkeyed (nearby :: unkeyed)
    in
    case styleChildren of
        [] ->
            Unstyled <| renderNode rendered.alignment rendered.node rendered.attributes renderedChildren Nothing

        _ ->
            Styled
                { styles = styleChildren
                , html = renderNode rendered.alignment rendered.node rendered.attributes renderedChildren
                }


type RenderMode
    = Viewport
    | Layout
    | NoStaticStyleSheet
    | WithVirtualCss


type alias Options =
    { hover : HoverOption
    , focus : FocusStyle
    }


type HoverOption
    = NoHover
    | AllowHover
    | ForceHover


type alias Shadow =
    { color : Color
    , offset : ( Int, Int )
    , blur : Int
    , size : Int
    }



-- formatBoxShadow : { e | blur : a, color : Color, inset : Bool, offset : ( b, c ), size : d }


type alias FocusStyle =
    { borderColor : Maybe Color
    , shadow : Maybe Shadow
    , backgroundColor : Maybe Color
    }



-- renderStyles : Element msg -> ( Set String, List Style ) -> ( Set String, List Style )
-- renderStyles el ( cache, existing ) =
--     case el of
--         Unstyled html ->
--             ( cache, existing )
--         Styled styled ->
--             let
--                 reduced =
--                     List.foldr reduceStyles ( cache, existing ) styled.styles
--             in
--             List.foldr renderStyles reduced styled.children


optionStyles : Options -> Style
optionStyles options =
    Style ".se:focus"
        (List.filterMap identity
            [ Maybe.map (\color -> Property "border-color" (formatColor color)) options.focus.borderColor
            , Maybe.map (\color -> Property "background-color" (formatColor color)) options.focus.backgroundColor
            , Maybe.map
                (\shadow ->
                    Property "box-shadow"
                        (formatBoxShadow
                            { color = shadow.color
                            , offset = shadow.offset
                            , inset = False
                            , blur = shadow.blur
                            , size = shadow.size
                            }
                        )
                )
                options.focus.shadow
            , Just <| Property "outline" "none"
            ]
        )



-- Class (class Any ++ ":focus")
--             [ Prop "border-color" "rgba(155,203,255,1.0)"
--             , Prop "box-shadow" "0 0 3px 3px rgba(155,203,255,1.0)"
--             , Prop "outline" "none"
--             ]


{-| -}
renderRoot : Options -> RenderMode -> List (Attribute msg) -> Element msg -> Html msg
renderRoot options mode attributes child =
    let
        rendered =
            renderAttributes Nothing [] attributes

        ( htmlChildren, styleChildren ) =
            case child of
                Unstyled html ->
                    ( html asEl, rendered.styles )

                Styled styled ->
                    ( styled.html Nothing asEl, styled.styles ++ rendered.styles )

                Text str ->
                    ( textElement str
                    , rendered.styles
                    )

                Empty ->
                    ( Html.text "", rendered.styles )

        styles =
            styleChildren
                |> List.foldr reduceStyles ( Set.empty, [ optionStyles options ] )
                -- |> renderStyles child
                |> Tuple.second

        styleSheets children =
            case mode of
                NoStaticStyleSheet ->
                    toStyleSheet options styles :: children

                Layout ->
                    Internal.Style.rulesElement
                        :: toStyleSheet options styles
                        :: children

                Viewport ->
                    Internal.Style.viewportRulesElement
                        :: toStyleSheet options styles
                        :: children

                WithVirtualCss ->
                    let
                        _ =
                            toStyleSheetVirtualCss styles
                    in
                    Internal.Style.rulesElement
                        :: children

        children =
            case Maybe.map renderNearbyGroupAbsolute rendered.nearbys of
                Nothing ->
                    styleSheets [ htmlChildren ]

                Just nearby ->
                    styleSheets [ nearby, htmlChildren ]
    in
    -- The top node cannot be keyed
    renderNode rendered.alignment rendered.node rendered.attributes (Unkeyed children) Nothing asEl


htmlClass : String -> Attribute msg
htmlClass cls =
    Attr <| VirtualDom.property "className" (Json.string cls)


renderFont : List Font -> String
renderFont families =
    let
        renderFont font =
            case font of
                Serif ->
                    "serif"

                SansSerif ->
                    "sans-serif"

                Monospace ->
                    "monospace"

                Typeface name ->
                    "\"" ++ name ++ "\""

                ImportFont name url ->
                    "\"" ++ name ++ "\""
    in
    families
        |> List.map renderFont
        |> String.join ", "


reduceStyles : Style -> ( Set String, List Style ) -> ( Set String, List Style )
reduceStyles style ( cache, existing ) =
    let
        styleName =
            getStyleName style
    in
    if Set.member styleName cache then
        ( cache, existing )
    else
        ( Set.insert styleName cache
        , style :: existing
        )


toStyleSheet : Options -> List Style -> VirtualDom.Node msg
toStyleSheet options styleSheet =
    VirtualDom.node "style" [] [ Html.text (toStyleSheetString options styleSheet) ]


toStyleSheetString : Options -> List Style -> String
toStyleSheetString options stylesheet =
    let
        renderProps force (Property key val) existing =
            if force then
                existing ++ "\n  " ++ key ++ ": " ++ val ++ " !important;"
            else
                existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

        renderStyle force maybePseudo selector props =
            case maybePseudo of
                Nothing ->
                    selector ++ "{" ++ List.foldl (renderProps force) "" props ++ "\n}"

                Just pseudo ->
                    selector ++ ":" ++ pseudo ++ " {" ++ List.foldl (renderProps force) "" props ++ "\n}"

        renderStyleRule rule maybePseudo force =
            case rule of
                Style selector props ->
                    renderStyle force maybePseudo selector props

                FontSize i ->
                    renderStyle force
                        maybePseudo
                        (".font-size-" ++ toString (isInt i))
                        [ Property "font-size" (toString i)
                        ]

                FontFamily name typefaces ->
                    renderStyle force
                        maybePseudo
                        ("." ++ name)
                        [ Property "font-family" (renderFont typefaces)
                        ]

                LineHeight i ->
                    renderStyle force
                        maybePseudo
                        (".line-height-" ++ floatClass i)
                        [ Property "line-height" (toString i)
                        ]

                Single class prop val ->
                    renderStyle force
                        maybePseudo
                        class
                        [ Property prop val
                        ]

                Colored class prop color ->
                    renderStyle force
                        maybePseudo
                        class
                        [ Property prop (formatColor color)
                        ]

                SpacingStyle x y ->
                    let
                        class =
                            ".spacing-" ++ toString x ++ "-" ++ toString y
                    in
                    List.foldl (++)
                        ""
                        [ renderStyle force maybePseudo (class ++ ".row > .se") [ Property "margin-left" (toString x ++ "px") ]
                        , renderStyle force maybePseudo (class ++ ".column > .se") [ Property "margin-top" (toString y ++ "px") ]
                        , renderStyle force maybePseudo (class ++ ".page > .se") [ Property "margin-top" (toString y ++ "px") ]
                        , renderStyle force maybePseudo (class ++ ".page > .self-left") [ Property "margin-right" (toString x ++ "px") ]
                        , renderStyle force maybePseudo (class ++ ".page > .self-right") [ Property "margin-left" (toString x ++ "px") ]
                        ]

                PaddingStyle top right bottom left ->
                    let
                        class =
                            ".pad-"
                                ++ toString top
                                ++ "-"
                                ++ toString right
                                ++ "-"
                                ++ toString bottom
                                ++ "-"
                                ++ toString left
                    in
                    renderStyle force
                        maybePseudo
                        class
                        [ Property "padding"
                            (toString top
                                ++ "px "
                                ++ toString right
                                ++ "px "
                                ++ toString bottom
                                ++ "px "
                                ++ toString left
                                ++ "px"
                            )
                        ]

                GridTemplateStyle template ->
                    let
                        class =
                            ".grid-"
                                ++ String.join "-" (List.map lengthClassName template.rows)
                                ++ "-"
                                ++ String.join "-" (List.map lengthClassName template.columns)
                                ++ "-"
                                ++ lengthClassName (Tuple.first template.spacing)
                                ++ "-"
                                ++ lengthClassName (Tuple.second template.spacing)

                        ySpacing =
                            toGridLength (Tuple.second template.spacing)

                        xSpacing =
                            toGridLength (Tuple.first template.spacing)

                        toGridLength x =
                            case x of
                                Px px ->
                                    toString px ++ "px"

                                Content ->
                                    "auto"

                                Fill i ->
                                    toString i ++ "fr"

                        msColumns =
                            template.columns
                                |> List.map toGridLength
                                |> String.join ySpacing
                                |> (\x -> "-ms-grid-columns: " ++ x ++ ";")

                        msRows =
                            template.columns
                                |> List.map toGridLength
                                |> String.join ySpacing
                                |> (\x -> "-ms-grid-rows: " ++ x ++ ";")

                        base =
                            class ++ "{" ++ msColumns ++ msRows ++ "}"

                        columns =
                            template.columns
                                |> List.map toGridLength
                                |> String.join " "
                                |> (\x -> "grid-template-columns: " ++ x ++ ";")

                        rows =
                            template.rows
                                |> List.map toGridLength
                                |> String.join " "
                                |> (\x -> "grid-template-rows: " ++ x ++ ";")

                        gapX =
                            "grid-column-gap:" ++ toGridLength (Tuple.first template.spacing) ++ ";"

                        gapY =
                            "grid-row-gap:" ++ toGridLength (Tuple.first template.spacing) ++ ";"

                        modernGrid =
                            class ++ "{" ++ columns ++ rows ++ gapX ++ gapY ++ "}"

                        supports =
                            "@supports (display:grid) {" ++ modernGrid ++ "}"
                    in
                    base ++ supports

                GridPosition position ->
                    let
                        class =
                            ".grid-pos-"
                                ++ toString position.row
                                ++ "-"
                                ++ toString position.col
                                ++ "-"
                                ++ toString position.width
                                ++ "-"
                                ++ toString position.height

                        msPosition =
                            String.join " "
                                [ "-ms-grid-row: "
                                    ++ toString position.row
                                    ++ ";"
                                , "-ms-grid-row-span: "
                                    ++ toString position.height
                                    ++ ";"
                                , "-ms-grid-column: "
                                    ++ toString position.col
                                    ++ ";"
                                , "-ms-grid-column-span: "
                                    ++ toString position.width
                                    ++ ";"
                                ]

                        base =
                            class ++ "{" ++ msPosition ++ "}"

                        modernPosition =
                            String.join " "
                                [ "grid-row: "
                                    ++ toString position.row
                                    ++ " / "
                                    ++ toString (position.row + position.width)
                                    ++ ";"
                                , "grid-column: "
                                    ++ toString position.col
                                    ++ " / "
                                    ++ toString (position.col + position.height)
                                    ++ ";"
                                ]

                        modernGrid =
                            class ++ "{" ++ modernPosition ++ "}"

                        supports =
                            "@supports (display:grid) {" ++ modernGrid ++ "}"
                    in
                    base ++ supports

                PseudoSelector class style ->
                    case class of
                        Focus ->
                            renderStyleRule style (Just "focus") False

                        Hover ->
                            case options.hover of
                                NoHover ->
                                    ""

                                AllowHover ->
                                    renderStyleRule style (Just "hover") False

                                ForceHover ->
                                    renderStyleRule style Nothing True

        combine style rendered =
            rendered ++ renderStyleRule style Nothing False
    in
    List.foldl combine "" stylesheet


lengthClassName : Length -> String
lengthClassName x =
    case x of
        Px px ->
            toString px ++ "px"

        Content ->
            "auto"

        Fill i ->
            toString i ++ "fr"


formatDropShadow : { d | blur : a, color : Color, offset : ( b, c ) } -> String
formatDropShadow shadow =
    String.join " "
        [ toString (Tuple.first shadow.offset) ++ "px"
        , toString (Tuple.second shadow.offset) ++ "px"
        , toString shadow.blur ++ "px"
        , formatColor shadow.color
        ]


formatTextShadow : { d | blur : a, color : Color, offset : ( b, c ) } -> String
formatTextShadow shadow =
    String.join " "
        [ toString (Tuple.first shadow.offset) ++ "px"
        , toString (Tuple.second shadow.offset) ++ "px"
        , toString shadow.blur ++ "px"
        , formatColor shadow.color
        ]


formatBoxShadow : { e | blur : a, color : Color, inset : Bool, offset : ( b, c ), size : d } -> String
formatBoxShadow shadow =
    String.join " " <|
        List.filterMap identity
            [ if shadow.inset then
                Just "inset"
              else
                Nothing
            , Just <| toString (Tuple.first shadow.offset) ++ "px"
            , Just <| toString (Tuple.second shadow.offset) ++ "px"
            , Just <| toString shadow.blur ++ "px"
            , Just <| toString shadow.size ++ "px"
            , Just <| formatColor shadow.color
            ]


filterName : FilterType -> String
filterName filtr =
    case filtr of
        FilterUrl url ->
            "url(" ++ url ++ ")"

        Blur x ->
            "blur(" ++ toString x ++ "px)"

        Brightness x ->
            "brightness(" ++ toString x ++ "%)"

        Contrast x ->
            "contrast(" ++ toString x ++ "%)"

        Grayscale x ->
            "grayscale(" ++ toString x ++ "%)"

        HueRotate x ->
            "hueRotate(" ++ toString x ++ "deg)"

        Invert x ->
            "invert(" ++ toString x ++ "%)"

        OpacityFilter x ->
            "opacity(" ++ toString x ++ "%)"

        Saturate x ->
            "saturate(" ++ toString x ++ "%)"

        Sepia x ->
            "sepia(" ++ toString x ++ "%)"

        DropShadow shadow ->
            let
                shadowModel =
                    { offset = shadow.offset
                    , size = shadow.size
                    , blur = shadow.blur
                    , color = shadow.color
                    }
            in
            "drop-shadow(" ++ formatDropShadow shadowModel ++ ")"


floatClass : Float -> String
floatClass x =
    toString <| round (x * 100)


formatColor : Color -> String
formatColor color =
    let
        { red, green, blue, alpha } =
            Color.toRgb color
    in
    ("rgba(" ++ toString red)
        ++ ("," ++ toString green)
        ++ ("," ++ toString blue)
        ++ ("," ++ toString alpha ++ ")")


formatColorClass : Color -> String
formatColorClass color =
    let
        { red, green, blue, alpha } =
            Color.toRgb color
    in
    toString red
        ++ "-"
        ++ toString green
        ++ "-"
        ++ toString blue
        ++ "-"
        ++ floatClass alpha


toStyleSheetVirtualCss : List Style -> ()
toStyleSheetVirtualCss stylesheet =
    case stylesheet of
        [] ->
            ()

        styles ->
            let
                renderProps (Property key val) existing =
                    existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

                renderStyle selector props =
                    selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

                _ =
                    VirtualCss.clear ()

                combine style cache =
                    case style of
                        Style selector props ->
                            let
                                _ =
                                    VirtualCss.insert (renderStyle selector props) 0
                            in
                            cache

                        Single class prop val ->
                            if Set.member class cache then
                                cache
                            else
                                let
                                    _ =
                                        VirtualCss.insert (class ++ "{" ++ prop ++ ":" ++ val ++ "}") 0
                                in
                                Set.insert class cache

                        Colored class prop color ->
                            if Set.member class cache then
                                cache
                            else
                                let
                                    _ =
                                        VirtualCss.insert (class ++ "{" ++ prop ++ ":" ++ formatColor color ++ "}") 0
                                in
                                Set.insert class cache

                        SpacingStyle x y ->
                            let
                                class =
                                    ".spacing-" ++ toString x ++ "-" ++ toString y
                            in
                            if Set.member class cache then
                                cache
                            else
                                -- TODO!
                                cache

                        -- ( rendered ++ spacingClasses class x y
                        -- , Set.insert class cache
                        -- )
                        PaddingStyle top right bottom left ->
                            let
                                class =
                                    ".pad-"
                                        ++ toString top
                                        ++ "-"
                                        ++ toString right
                                        ++ "-"
                                        ++ toString bottom
                                        ++ "-"
                                        ++ toString left
                            in
                            if Set.member class cache then
                                cache
                            else
                                -- TODO!
                                cache

                        LineHeight _ ->
                            cache

                        GridTemplateStyle _ ->
                            cache

                        GridPosition _ ->
                            cache

                        FontFamily _ _ ->
                            cache

                        FontSize _ ->
                            cache

                        PseudoSelector _ _ ->
                            cache

                -- ( rendered ++ paddingClasses class top right bottom left
                -- , Set.insert class cache
                -- )
            in
            List.foldl combine Set.empty styles
                |> always ()


psuedoClassName class =
    case class of
        Focus ->
            "focus"

        Hover ->
            "hover"


{-| This is a key to know which styles should override which other styles.
-}
styleKey : Style -> String
styleKey style =
    case style of
        Style class _ ->
            class

        FontSize i ->
            "fontsize"

        FontFamily _ _ ->
            "fontfamily"

        Single _ prop _ ->
            prop

        LineHeight _ ->
            "lineheight"

        Colored _ prop _ ->
            prop

        SpacingStyle _ _ ->
            "spacing"

        PaddingStyle _ _ _ _ ->
            "padding"

        GridTemplateStyle _ ->
            "grid-template"

        GridPosition _ ->
            "grid-position"

        PseudoSelector class style ->
            psuedoClassName class ++ styleKey style


isInt : Int -> Int
isInt x =
    x


getStyleName : Style -> String
getStyleName style =
    case style of
        Style class _ ->
            class

        LineHeight i ->
            "line-height-" ++ floatClass i

        FontFamily name _ ->
            name

        FontSize i ->
            "font-size-" ++ toString (isInt i)

        Single class _ _ ->
            class

        Colored class _ _ ->
            class

        SpacingStyle x y ->
            "spacing-" ++ toString (isInt x) ++ "-" ++ toString (isInt y)

        PaddingStyle top right bottom left ->
            "pad-"
                ++ toString top
                ++ "-"
                ++ toString right
                ++ "-"
                ++ toString bottom
                ++ "-"
                ++ toString left

        GridTemplateStyle template ->
            "grid-"
                ++ String.join "-" (List.map lengthClassName template.rows)
                ++ "-"
                ++ String.join "-" (List.map lengthClassName template.columns)
                ++ "-"
                ++ lengthClassName (Tuple.first template.spacing)
                ++ "-"
                ++ lengthClassName (Tuple.second template.spacing)

        GridPosition pos ->
            "grid-pos-"
                ++ toString pos.row
                ++ "-"
                ++ toString pos.col
                ++ "-"
                ++ toString pos.width
                ++ "-"
                ++ toString pos.height

        PseudoSelector selector subStyle ->
            getStyleName subStyle


locationClass : Location -> String
locationClass location =
    case location of
        Above ->
            "se el above"

        Below ->
            "se el below"

        OnRight ->
            "se el on-right"

        OnLeft ->
            "se el on-left"

        InFront ->
            "se el infront"

        Behind ->
            "se el behind"
