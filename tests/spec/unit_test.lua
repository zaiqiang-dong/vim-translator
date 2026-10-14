-- vim-translator 单元测试（headless 运行）
local t = require("vim-translator.text")

-- 方向检测
assert(t.detect_target("你好") == "en", "zh->en failed")
assert(t.detect_target("hello") == "zh", "en->zh failed")
assert(t.detect_target("中英mixed") == "en", "mixed failed")

-- 单词判定
assert(t.is_word("hello") == true, "is_word en failed")
assert(t.is_word("hello world") == false, "is_word spaces failed")
assert(t.is_word("你好") == true, "is_word zh failed")
assert(t.is_word("don't") == true, "is_word apostrophe failed")

-- is_word 对单行长句应为 false
assert(t.is_word(("x"):rep(41)) == false, "is_word length failed")

print("UNIT_TEST all passed")
