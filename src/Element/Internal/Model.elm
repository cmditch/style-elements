module Element.Internal.Model exposing (..)

{-| -}

import Element.Style.Internal.Model as Internal
import Html exposing (Html)


type Element elem variation
    = Empty
    | Text Decoration String
    | Element (Maybe elem) (List (Attribute variation)) (Element elem variation)
    | Layout Internal.LayoutModel (Maybe elem) (List (Attribute variation)) (List (Element elem variation))


type Attribute variation
    = Variations (List ( Bool, variation ))
    | Height Internal.Length
    | Width Internal.Length
    | Position Int Int
    | PositionFrame Frame
    | Anchor AnchorPoint
    | Spacing ( Float, Float, Float, Float )
    | Hidden
    | Transparency Int


type Decoration
    = NoDecoration
    | Bold
    | Italic
    | Underline
    | Strike


type Frame
    = Below
    | Above
    | OnLeft
    | OnRight
    | Screen


type AnchorPoint
    = Left
    | Right
    | Top
    | Bottom


type alias HtmlFn msg =
    List (Html.Attribute msg) -> List (Html msg) -> Html msg


type Styled elem variation animation msg
    = El (HtmlFn msg) (List (StyleAttribute elem variation animation msg))


type StyleAttribute elem variation animation msg
    = Attr (Html.Attribute msg)
    | Style (Internal.Property elem variation animation)
