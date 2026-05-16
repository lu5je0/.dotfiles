; extends

; single paragraph (no blank lines between @startuml and @enduml)
((paragraph
  (inline) @_check) @injection.content
  (#lua-match? @_check "@startuml")
  (#lua-match? @_check "@enduml")
  (#set! injection.language "plantuml")
  (#set! injection.include-children))

; multi-paragraph: section starts with @startuml, inject the startuml paragraph + all following
(section
  (paragraph
    (inline) @_check
    (#lua-match? @_check "@startuml")
    (#not-lua-match? @_check "@enduml")) @injection.content
  (paragraph)+ @injection.content
  (#set! injection.language "plantuml")
  (#set! injection.combined)
  (#set! injection.include-children))
