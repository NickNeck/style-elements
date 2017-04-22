module Elements exposing (..)

{-| -}

import Html exposing (Html)
import Html.Attributes
import Style.Internal.Model as Internal
import Style.Internal.Render.Value as Value
import Style.Internal.Cache as StyleCache
import Style.Internal.Render as Render
import Style.Internal.Selector as Selector
import Style.Internal.Intermediate as Intermediate exposing (Rendered(..))


type Element elem variation
    = Empty
    | Layout Internal.LayoutModel elem (List (LayoutAttribute variation)) (List (Element elem variation))
    | Element elem (List (LayoutAttribute variation)) (Element elem variation)
    | Text String


type LayoutAttribute variation
    = Variations (List ( Bool, variation ))
    | Height Internal.Length
    | Width Internal.Length
    | Position Int Int
    | Spacing Float Float Float Float
    | Hidden
    | Transparency Int


(=>) =
    (,)


type WithSpacing
    = InlineSpacing
    | NoSpacing


renderInline : WithSpacing -> List (LayoutAttribute variation) -> List ( String, String )
renderInline spacing adjustments =
    let
        renderAdjustment adj =
            case adj of
                Variations variations ->
                    []

                Height len ->
                    [ "height" => Value.length len ]

                Width len ->
                    [ "width" => Value.length len ]

                Position x y ->
                    []

                Spacing a b c d ->
                    case spacing of
                        InlineSpacing ->
                            [ "margin" => Value.box ( a, b, c, d ) ]

                        NoSpacing ->
                            []

                Hidden ->
                    [ "display" => "none" ]

                Transparency t ->
                    [ "opacity" => (toString <| 1 - t) ]
    in
        List.concatMap renderAdjustment adjustments



-- toInternalProps : Maybe Internal.LayoutModel -> List LayoutAttribute variation -> List (Internal.Property class variation animation)
-- toInternalProps maybeLayout attributes =
--     let
--         renderProp attr ( mLayout, props ) =
--             case attr of
--                 Variations _ ->
--                     ( mLayout, props )
--                 Height len ->
--                     ( mLayout, Internal.Exact "height" (Value.length len) :: props )
--                 Width len ->
--                     ( mLayout, Internal.Exact "width" (Value.length len) :: props )
--                 Position x y ->
--                     ( mLayout
--                     , Internal.Position
--                         [ Internal.RelativeTo Internal.Current
--                         , Internal.PosLeft x
--                         , Internal.PosTop y
--                         ]
--                         :: props
--                     )
--                 Spacing a b c d ->
--                     case mLayout of
--                         Nothing ->
--                             ( mLayout, Internal.Exact "margin" (Value.box ( a, b, c, d )) :: props )
--                         Just layout ->
--                             let
--                                 newLayout =
--                                     case layout of
--                                         Internal.TextLayout _ ->
--                                             Internal.TextLayout { spacing = Just ( a, b, c, d ) }
--                                         Internal.FlexLayout dir layoutProps ->
--                                             Internal.FlexLayout dir (layoutProps ++ Internal.Spacing ( a, b, c, d ))
--                             in
--                                 ( Just newLayout, props )
--                 Hidden ->
--                     ( mLayout, Internal.Visibility (Internal.Hidden) :: props )
--                 Transparency o ->
--                     ( mLayout, Internal.Visibility (Internal.Opacity (1.0 - o)) :: props )
--     in
--         List.foldr renderProp ( maybeLayout, [] ) attributes


type alias HtmlFn msg =
    List (Html.Attribute msg) -> List (Html msg) -> Html msg


type Styled elem variation animation msg
    = El (HtmlFn msg) (List (Attributes elem variation animation msg))


type Attributes elem variation animation msg
    = Attr (Html.Attribute msg)
    | Style (Internal.Property elem variation animation)


attr =
    Attr


style =
    Style


{-| In Heirarchy

-}
empty : Element elem variation
empty =
    Empty


text : String -> Element elem variation
text =
    Text


el : elem -> List (LayoutAttribute variation) -> Element elem variation -> Element elem variation
el =
    Element


row : elem -> List (LayoutAttribute variation) -> List (Element elem variation) -> Element elem variation
row elem attrs children =
    Layout (Internal.FlexLayout Internal.GoRight []) elem attrs children


column : elem -> List (LayoutAttribute variation) -> List (Element elem variation) -> Element elem variation
column elem attrs children =
    Layout (Internal.FlexLayout Internal.Down []) elem attrs children



-- centered : elem -> List (LayoutAttribute variation) -> Element elem variation -> Element elem variation
-- centered elem attrs child =
--     Element elem (HCenter :: attrs) child
-- Relative Positioning


above : Element elem variation -> Element elem variation -> Element elem variation
above a b =
    b


below : Element elem variation -> Element elem variation -> Element elem variation
below a b =
    b


toRight : Element elem variation -> Element elem variation -> Element elem variation
toRight a b =
    b


toLeft : Element elem variation -> Element elem variation -> Element elem variation
toLeft a b =
    b



--
-- from topLeft
-- screen : Element elem variation -> Element elem variation
-- screen =
--     identity
-- overlay : elem -> Element elem variation -> Element elem variation
-- overlay bg child =
--     screen <| Element bg [ width (percent 100), height (percent 100) ] child


{-| A synonym for the identity function.  Useful for relative
-}
nevermind : a -> a
nevermind =
    identity



--
-- In your attribute sheet


element : List (Attributes elem variation animation msg) -> Styled elem variation animation msg
element =
    El Html.div


elementAs : HtmlFn msg -> List (Attributes elem variation animation msg) -> Styled elem variation animation msg
elementAs =
    El



--- Rendering


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

        Text str ->
            ( Html.text str, StyleCache.empty )

        Element element position child ->
            let
                ( childHtml, styleset ) =
                    renderElement findNode child

                elemHtml =
                    renderNode element (renderInline InlineSpacing position) (findNode element) [ childHtml ]
            in
                ( elemHtml
                , styleset
                    |> StyleCache.insert element
                )

        Layout layout element position children ->
            let
                -- parentPositionalStyle =
                --     Internal.Style
                --         [ Internal.Layout layout :: List.map toInternalProps
                --         ]
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
                        Spacing a b c d ->
                            Just ( a, b, c, d )

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

                parent =
                    renderLayoutNode element (Maybe.map spacingName spacing) (renderInline NoSpacing position) (findNode element) childHtml
            in
                ( parent
                , styleset
                    |> StyleCache.insert element
                    |> addSpacing
                )


renderNode : elem -> List ( String, String ) -> Styled elem variation animation msg -> List (Html msg) -> Html msg
renderNode elem inlineStyle (El node attrs) children =
    let
        normalAttrs attr =
            case attr of
                Attr a ->
                    Just a

                _ ->
                    Nothing

        attributes =
            List.filterMap normalAttrs attrs

        styleName =
            Html.Attributes.class (Selector.formatName elem)
    in
        node (Html.Attributes.style inlineStyle :: styleName :: attributes) children


renderLayoutNode : elem -> Maybe String -> List ( String, String ) -> Styled elem variation animation msg -> List (Html msg) -> Html msg
renderLayoutNode elem mSpacingClass inlineStyle (El node attrs) children =
    let
        normalAttrs attr =
            case attr of
                Attr a ->
                    Just a

                _ ->
                    Nothing

        attributes =
            List.filterMap normalAttrs attrs

        classes =
            case mSpacingClass of
                Nothing ->
                    Html.Attributes.class (Selector.formatName elem)

                Just space ->
                    Html.Attributes.class <| Selector.formatName elem ++ " " ++ space
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
