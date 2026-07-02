#!/usr/bin/env python3
# Converts text typed with the wrong input source between ABC (US) and Russian PC.
# Direction is guessed from the input: Cyrillic text (or the Latin Ë that Russian PC
# produces for Shift+`) is treated as Russian PC output and converted to ABC;
# otherwise it's converted from ABC to Russian PC.

EN_TO_RU = {
    "`": "ё", "~": "Ё",  # Russian PC actually emits Latin Ë, but Ё is what users want
    "@": '"', "#": "№", "$": ";", "^": ":", "&": "?",
    "q": "й", "Q": "Й",
    "w": "ц", "W": "Ц",
    "e": "у", "E": "У",
    "r": "к", "R": "К",
    "t": "е", "T": "Е",
    "y": "н", "Y": "Н",
    "u": "г", "U": "Г",
    "i": "ш", "I": "Ш",
    "o": "щ", "O": "Щ",
    "p": "з", "P": "З",
    "[": "х", "{": "Х",
    "]": "ъ", "}": "Ъ",
    "|": "/",
    "a": "ф", "A": "Ф",
    "s": "ы", "S": "Ы",
    "d": "в", "D": "В",
    "f": "а", "F": "А",
    "g": "п", "G": "П",
    "h": "р", "H": "Р",
    "j": "о", "J": "О",
    "k": "л", "K": "Л",
    "l": "д", "L": "Д",
    ";": "ж", ":": "Ж",
    "'": "э", '"': "Э",
    "z": "я", "Z": "Я",
    "x": "ч", "X": "Ч",
    "c": "с", "C": "С",
    "v": "м", "V": "М",
    "b": "и", "B": "И",
    "n": "т", "N": "Т",
    "m": "ь", "M": "Ь",
    ",": "б", "<": "Б",
    ".": "ю", ">": "Ю",
    "/": ".", "?": ",",
}

RU_TO_EN = {ru: en for en, ru in EN_TO_RU.items()}
# Russian PC emits Latin Ë for Shift+`; map it back to ~.
RU_TO_EN["Ë"] = "~"

def is_russian_layout_output(text):
    return any(ch == "Ë" or ("\u0400" <= ch <= "\u04ff") for ch in text)

import sys
text = sys.stdin.read()
table = RU_TO_EN if is_russian_layout_output(text) else EN_TO_RU
print("".join(table.get(ch, ch) for ch in text), end="")
