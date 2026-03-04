((string) @injection.content
 (#match? @injection.content "^'.*'$")
 (#match? @injection.content "([=!<>]=|&&|\\|\\||\\binstanceof\\b|\\bnull\\b)")
 (#not-match? @injection.content "^'\\{.*\\}'$")
 (#set! injection.language "java")
 (#offset! @injection.content 0 1 0 -1))
