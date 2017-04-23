module Element.Internal.Render exposing (..)

{-| -}

import Html exposing (Html)
import Html.Attributes
import Element.Style.Internal.Model as Internal exposing (Length)
import Element.Style.Internal.Render.Value as Value
import Element.Style.Internal.Cache as StyleCache
import Element.Style.Internal.Render as Render
import Element.Style.Internal.Selector as Selector
import Element.Style.Internal.Render.Property
import Element.Internal.Model exposing (..)


(=>) =
    (,)


render : (elem -> Styled elem variation animation msg) -> Element elem variation -> Html msg
render findNode elm =
    let
        ( html, stylecache ) =
            renderElement findNode elm
    in
        Html.div []
            [ StyleCache.render stylecache renderStyle findNode
            , html
            ]


renderElement : (elem -> Styled elem variation animation msg) -> Element elem variation -> ( Html msg, StyleCache.Cache elem )
renderElement findNode elm =
    case elm of
        Empty ->
            ( Html.text "", StyleCache.empty )

        Text dec str ->
            case dec of
                NoDecoration ->
                    ( Html.text str, StyleCache.empty )

                Bold ->
                    ( Html.strong [] [ Html.text str ], StyleCache.empty )

                Italic ->
                    ( Html.em [] [ Html.text str ], StyleCache.empty )

                Underline ->
                    ( Html.u [] [ Html.text str ], StyleCache.empty )

                Strike ->
                    ( Html.s [] [ Html.text str ], StyleCache.empty )

        Element element position child ->
            let
                ( childHtml, styleset ) =
                    renderElement findNode child
            in
                case element of
                    Nothing ->
                        ( renderNode Nothing (renderInline InlineSpacing position) Nothing [ childHtml ]
                        , styleset
                        )

                    Just el ->
                        ( renderNode element (renderInline InlineSpacing position) (Just <| findNode el) [ childHtml ]
                        , styleset
                            |> StyleCache.insert el
                        )

        Layout layout maybeElement position children ->
            let
                parentStyle =
                    Element.Style.Internal.Render.Property.layout layout ++ renderInline NoSpacing position

                ( childHtml, styleset ) =
                    List.foldr renderAndCombine ( [], StyleCache.empty ) children

                renderAndCombine child ( html, styles ) =
                    let
                        ( childHtml, childStyle ) =
                            renderElement findNode child
                    in
                        ( childHtml :: html, StyleCache.combine childStyle styles )

                forSpacing posAttr =
                    case posAttr of
                        Spacing box ->
                            Just box

                        _ ->
                            Nothing

                spacing =
                    position
                        |> List.filterMap forSpacing
                        |> List.head

                spacingName ( a, b, c, d ) =
                    "spacing-" ++ toString a ++ "-" ++ toString b ++ "-" ++ toString c ++ "-" ++ toString d

                addSpacing cache =
                    case spacing of
                        Nothing ->
                            cache

                        Just space ->
                            let
                                ( name, rendered ) =
                                    Render.spacing space
                            in
                                StyleCache.embed name rendered cache
            in
                case maybeElement of
                    Nothing ->
                        ( renderLayoutNode Nothing (Maybe.map spacingName spacing) parentStyle Nothing childHtml
                        , styleset
                            |> addSpacing
                        )

                    Just element ->
                        ( renderLayoutNode (Just element) (Maybe.map spacingName spacing) parentStyle (Just <| findNode element) childHtml
                        , styleset
                            |> StyleCache.insert element
                            |> addSpacing
                        )


renderNode : Maybe elem -> List ( String, String ) -> Maybe (Styled elem variation animation msg) -> List (Html msg) -> Html msg
renderNode maybeElem inlineStyle maybeNode children =
    let
        ( node, attrs ) =
            case maybeNode of
                Nothing ->
                    ( Html.div, [] )

                Just (El node attrs) ->
                    ( node, attrs )

        normalAttrs attr =
            case attr of
                Attr a ->
                    Just a

                _ ->
                    Nothing

        attributes =
            List.filterMap normalAttrs attrs

        renderedAttrs =
            case maybeElem of
                Nothing ->
                    (Html.Attributes.style inlineStyle :: attributes)

                Just elem ->
                    (Html.Attributes.style inlineStyle :: Html.Attributes.class (Selector.formatName elem) :: attributes)
    in
        node renderedAttrs children


renderLayoutNode : Maybe elem -> Maybe String -> List ( String, String ) -> Maybe (Styled elem variation animation msg) -> List (Html msg) -> Html msg
renderLayoutNode maybeElem mSpacingClass inlineStyle maybeNode children =
    let
        ( node, attrs ) =
            case maybeNode of
                Nothing ->
                    ( Html.div, [] )

                Just (El node attrs) ->
                    ( node, attrs )

        normalAttrs attr =
            case attr of
                Attr a ->
                    Just a

                _ ->
                    Nothing

        attributes =
            List.filterMap normalAttrs attrs

        elemClass =
            case maybeElem of
                Nothing ->
                    Nothing

                Just elem ->
                    Just <| Selector.formatName elem

        classes =
            Html.Attributes.class (String.join " " <| List.filterMap identity [ elemClass, mSpacingClass ])
    in
        node (Html.Attributes.style inlineStyle :: classes :: attributes) children


renderStyle : elem -> Styled elem variation animation msg -> Internal.Style elem variation animation
renderStyle elem (El node attrs) =
    let
        styleProps attr =
            case attr of
                Style a ->
                    Just a

                _ ->
                    Nothing
    in
        Internal.Style elem (List.filterMap styleProps attrs)


type WithSpacing
    = InlineSpacing
    | NoSpacing


renderInline : WithSpacing -> List (Attribute variation) -> List ( String, String )
renderInline spacing adjustments =
    let
        defaults =
            [ "position" => "relative"
            ]

        renderAdjustment adj =
            case adj of
                Variations variations ->
                    []

                Height len ->
                    [ "height" => Value.length len ]

                Width len ->
                    [ "width" => Value.length len ]

                Position x y ->
                    [ "transform" => ("translate(" ++ toString x ++ "px, " ++ toString y ++ "px)")
                    ]

                PositionFrame Screen ->
                    [ "position" => "fixed"
                    ]

                PositionFrame Above ->
                    [ "position" => "absolute"
                    , "bottom" => "100%"
                    ]

                PositionFrame Below ->
                    [ "position" => "absolute"
                    , "top" => "100%"
                    ]

                PositionFrame OnLeft ->
                    [ "position" => "absolute"
                    , "right" => "100%"
                    ]

                PositionFrame OnRight ->
                    [ "position" => "absolute"
                    , "left" => "100%"
                    ]

                Anchor Left ->
                    [ "left" => "0" ]

                Anchor Top ->
                    [ "top" => "0" ]

                Anchor Bottom ->
                    [ "bottom" => "0" ]

                Anchor Right ->
                    [ "right" => "0" ]

                Spacing box ->
                    case spacing of
                        InlineSpacing ->
                            [ "margin" => Value.box box ]

                        NoSpacing ->
                            []

                Hidden ->
                    [ "display" => "none" ]

                Transparency t ->
                    [ "opacity" => (toString <| 1 - t) ]
    in
        defaults ++ List.concatMap renderAdjustment adjustments
