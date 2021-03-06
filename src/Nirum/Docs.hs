module Nirum.Docs ( Block ( BlockQuote
                          , CodeBlock
                          , Document
                          , Heading
                          , HtmlBlock
                          , List
                          , Paragraph
                          , ThematicBreak
                          , infoString
                          , code
                          )
                  , HeadingLevel (H1, H2, H3, H4, H5, H6)
                  , Html
                  , Inline ( Code
                           , Emphasis
                           , HardLineBreak
                           , HtmlInline
                           , Image
                           , Link
                           , SoftLineBreak
                           , Strong
                           , Text
                           , imageTitle
                           , imageUrl
                           , linkContents
                           , linkTitle
                           , linkUrl
                           )
                  , ItemList (LooseItemList, TightItemList)
                  , ListType (BulletList, OrderedList, startNumber, delimiter)
                  , ListDelimiter (Parenthesis, Period)
                  , LooseItem
                  , TightItem
                  , Title
                  , Url
                  , filterReferences
                  , headingLevelFromInt
                  , headingLevelInt
                  , parse
                  , trimTitle
                  ) where

import Data.String (IsString (fromString))

import qualified CMark as M
import qualified Data.Text as T

type Url = T.Text
type Title = T.Text
type Html = T.Text

-- | The level of heading.
-- See also: http://spec.commonmark.org/0.25/#atx-heading
data HeadingLevel = H1 | H2 | H3 | H4 | H5 | H6 deriving (Eq, Ord, Show)

headingLevelFromInt :: Int -> HeadingLevel
headingLevelFromInt 2 = H2
headingLevelFromInt 3 = H3
headingLevelFromInt 4 = H4
headingLevelFromInt 5 = H5
headingLevelFromInt i = if i > 5 then H6 else H1

headingLevelInt :: HeadingLevel -> Int
headingLevelInt H1 = 1
headingLevelInt H2 = 2
headingLevelInt H3 = 3
headingLevelInt H4 = 4
headingLevelInt H5 = 5
headingLevelInt H6 = 6

-- | Whether a list is a bullet list or an ordered list.
-- See also: http://spec.commonmark.org/0.25/#of-the-same-type
data ListType = BulletList
              | OrderedList { startNumber :: Int
                            , delimiter :: ListDelimiter
                            }
              deriving (Eq, Ord, Show)

-- | Whether ordered list markers are followed by period (@.@) or
-- parenthesis (@)@).
-- See also: http://spec.commonmark.org/0.25/#ordered-list-marker
data ListDelimiter = Period | Parenthesis deriving (Eq, Ord, Show)

data Block = Document [Block]
           | ThematicBreak
           | Paragraph [Inline]
           | BlockQuote [Block]
           | HtmlBlock Html
           | CodeBlock { infoString :: T.Text, code :: T.Text }
           | Heading HeadingLevel [Inline]
           | List ListType ItemList
           deriving (Eq, Ord, Show)

data ItemList = LooseItemList [LooseItem]
              | TightItemList [TightItem]
              deriving (Eq, Ord, Show)

type LooseItem = [Block]

type TightItem = [Inline]

data Inline
    = Text T.Text
    | SoftLineBreak -- | See also:
                    -- http://spec.commonmark.org/0.25/#soft-line-breaks
    | HardLineBreak -- | See also:
                    -- http://spec.commonmark.org/0.25/#hard-line-breaks
    | HtmlInline Html
    | Code T.Text
    | Emphasis [Inline]
    | Strong [Inline]
    | Link { linkUrl :: Url, linkTitle :: Title, linkContents :: [Inline] }
    | Image { imageUrl :: Url, imageTitle :: Title }
    deriving (Eq, Ord, Show)

-- | Trim the top-level first heading from the block, if it exists.
trimTitle :: Block -> Block
trimTitle block =
    case block of
        Document (Heading {} : rest) -> Document rest
        b -> b

parse :: T.Text -> Block
parse =
    transBlock . M.commonmarkToNode [M.optNormalize, M.optSmart]
  where
    transBlock :: M.Node -> Block
    transBlock n@(M.Node _ nodeType children) =
        case nodeType of
            M.DOCUMENT -> Document blockChildren
            M.THEMATIC_BREAK -> ThematicBreak
            M.PARAGRAPH -> Paragraph inlineChildren
            M.BLOCK_QUOTE -> BlockQuote blockChildren
            M.HTML_BLOCK rawHtml -> HtmlBlock rawHtml
            M.CUSTOM_BLOCK _ _ -> error $ "custom block is unsupported: " ++ n'
            M.CODE_BLOCK info codeText -> CodeBlock info codeText
            M.HEADING lv -> Heading (headingLevelFromInt lv) inlineChildren
            M.LIST (M.ListAttributes listType' tight start delim) ->
                List (case listType' of
                          M.BULLET_LIST -> BulletList
                          M.ORDERED_LIST ->
                              OrderedList start $
                                          case delim of
                                              M.PERIOD_DELIM -> Period
                                              M.PAREN_DELIM -> Parenthesis
                     ) $
                     if tight
                        then TightItemList $ map stripParagraph listItems
                        else LooseItemList $ map (map transBlock) listItems
            _ -> error $ "expected block, but got inline: " ++ n'
      where
        blockChildren :: [Block]
        blockChildren = map transBlock children
        inlineChildren :: [Inline]
        inlineChildren = map transInline children
        listItems :: [[M.Node]]
        listItems = [nodes | (M.Node _ M.ITEM nodes) <- children]
        stripParagraph :: [M.Node] -> [Inline]
        stripParagraph [M.Node _ M.PARAGRAPH nodes] = map transInline nodes
        stripParagraph ns = error $ "expected a paragraph, but got " ++ show ns
        n' :: String
        n' = show n
    transInline :: M.Node -> Inline
    transInline n@(M.Node _ nodeType childNodes) =
        case nodeType of
            M.TEXT text -> Text text
            M.SOFTBREAK -> SoftLineBreak
            M.LINEBREAK -> HardLineBreak
            M.HTML_INLINE rawHtml -> HtmlInline rawHtml
            M.CODE code' -> Code code'
            M.EMPH -> Emphasis children
            M.STRONG -> Strong children
            M.LINK url title -> Link url title children
            M.IMAGE url title -> Image url title
            _ -> error $ "expected inline, but got block: " ++ show n
      where
        children :: [Inline]
        children = map transInline childNodes

instance IsString Block where
    fromString = parse . T.pack

instance IsString Inline where
    fromString = Text . T.pack

-- | Replace all 'Link' and 'Image' nodes with normal 'Text' nodes.
filterReferences :: [Inline] -> [Inline]
filterReferences [] = []
filterReferences (Image { imageTitle = t } : ix) = Text t : filterReferences ix
filterReferences (Link { linkContents = children } : ix) =
    children ++ filterReferences ix
filterReferences (i : ix) = i : filterReferences ix
