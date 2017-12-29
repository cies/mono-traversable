#!/usr/bin/env stack
-- stack runghc
import Data.List
import Control.Monad.Trans.Writer
import Control.Monad

main :: IO ()
main = do
    orig <- readFile "src/Data/Conduit/Combinators.hs"
    let origLines = map stripStreaming $ lines orig
        (exports, body) = break isImport $ drop 1 $ dropWhile (/= starting) origLines
        imports = takeWhile (/= "-- END IMPORTS") $ dropWhile (/= "-- BEGIN IMPORTS") origLines
        langs = filter ("{-# LANGUAGE " `isPrefixOf`) origLines
        docs = execWriter $ parseDocs $ filter (not . isCPP) body
        isCPP ('#':_) = True
        isCPP _ = False
        (x, y) = runWriter $ mapM process exports
    putStrLn "-- WARNING: This module is autogenerated"
    putStrLn "{-# OPTIONS_HADDOCK not-home #-}"
    mapM_ putStrLn langs
    putStrLn "module Data.Conduit.Combinators.Unqualified"
    mapM_ putStrLn x
    putStrLn "import qualified Data.Conduit.Combinators as CC"
    mapM_ putStrLn imports
    forM_ y $ \(old, new) -> do
        putStrLn ""
        case lookup old docs of
            Nothing -> putStrLn $ "-- | See 'CC." ++ old ++ "'"
            Just (docs', sig) -> do
                mapM_ putStrLn docs'
                forM_ sig $ \l -> putStrLn $
                    case stripPrefix old l of
                        Nothing -> l
                        Just l'' -> new ++ l''
        putStrLn $ new ++ " = CC." ++ old
        putStrLn $ "{-# INLINE " ++ new ++ " #-}"

starting :: String
starting = "module Data.Conduit.Combinators"

isImport :: String -> Bool
isImport = ("import " `isPrefixOf`)

isInlineRule :: String -> Bool
isInlineRule = ("INLINE_RULE" `isPrefixOf`)

parseDocs :: Monad m => [String] -> WriterT [(String, ([String], [String]))] m ()
parseDocs [] = return ()
parseDocs (x0:xs0)
    | isDoc x0 = loop (x0:) xs0
    | otherwise = parseDocs xs0
  where
    isDoc = ("--" `isPrefixOf`)

    loop _front [] = return ()
    loop front (x:xs)
        | isDoc x = loop (front . (x:)) xs
        | otherwise = loop2 (front []) id (x:xs)

    loop2 _docs _front [] = return ()
    loop2 docs front (x:xs)
        | '=' `elem` x && not (" => " `isInfixOf` x) = do
            let name = takeWhile (/= ' ') x
            when (null name) $ error $ "null name in loop2: " ++ show (docs, front [], x)
            let sig = front []
            when (null sig) $ error $ "Missing type signature on " ++ name
            tell [(name, (docs, front []))]
            parseDocs xs
        | isInlineRule x = do
            let sig = front []
                name = takeWhile (/= ' ') $ concat sig
            when (null sig) $ error $ "Missing type signature on " ++ name
            tell [(name, (docs, front []))]
            parseDocs xs
        | otherwise = loop2 docs (front . (x:)) xs

process :: Monad m => [Char] -> WriterT [([Char], [Char])] m [Char]
process l
    | null rest || head rest `elem` "(-)" = return $ dropLevel l
    | otherwise = do
        let orig =
                case dropWhile (/= '.') rest of
                    '.':orig' -> orig'
                    _ -> rest
            newName = tweak orig
        tell [(orig, newName)]
        return $ lead ++ newName
  where
    (lead, rest) = span (`elem` " ,") l

tweak :: [Char] -> [Char]
tweak orig
    | any (`isPrefixOf` orig) (words "await yield source sink conduit") = orig
    | otherwise =
        case reverse orig of
            'E':orig' -> reverse orig' ++ "CE"
            _ -> orig ++ "C"

dropLevel :: [Char] -> [Char]
dropLevel [] = []
dropLevel ('*':rest) = '*':'*':rest
dropLevel (x:y) = x : dropLevel y

stripStreaming :: String -> String
stripStreaming s0 =
  case break (== ',') s0 of
    (x, ',':' ':y0) ->
      let y = takeWhile (/= ' ') y0
       in if x ++ "C" == y
            then y0
            else s0
    _ -> s0
