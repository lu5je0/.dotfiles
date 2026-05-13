; extends

((paragraph
  (inline) @_check) @injection.content
  (#lua-match? @_check "@startuml")
  (#set! injection.language "plantuml")
  (#set! injection.combined)
  (#set! injection.include-children))

(section
  (paragraph
    (inline) @_check
    (#lua-match? @_check "@startuml"))
  (paragraph) @injection.content
  (#set! injection.language "plantuml")
  (#set! injection.combined)
  (#set! injection.include-children))
