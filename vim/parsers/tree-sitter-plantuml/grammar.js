module.exports = grammar({
  name: 'plantuml',

  extras: $ => [/[ \t\r]/],

  rules: {
    source_file: $ => seq(
      repeat(choice(seq($._line_content, $.newline), $.newline)),
      optional($._line_content)
    ),

    _line_content: $ => choice(
      $.comment,
      $.preprocessor,
      $.start_tag,
      $.end_tag,
      $.skinparam,
      $.activity_label,
      $.line,
    ),

    start_tag: _ => token(seq('@', choice(
      'startuml', 'startmindmap', 'startwbs', 'startgantt',
      'startsalt', 'startjson', 'startyaml', 'startditaa',
    ))),

    end_tag: _ => token(seq('@', choice(
      'enduml', 'endmindmap', 'endwbs', 'endgantt',
      'endsalt', 'endjson', 'endyaml', 'endditaa',
    ))),

    skinparam: $ => seq(
      alias(token('skinparam'), $.keyword),
      repeat(choice($.identifier, $.color, $.number)),
    ),

    preprocessor: _ => token(seq('!', /[a-zA-Z_]+/, /[^\n]*/)),

    activity_label: _ => token(seq(':', /[^;\n]+/, ';')),

    line: $ => seq(
      repeat1($._token),
      optional(seq($.arrow, repeat($._token))),
      optional($.colon_label),
    ),

    colon_label: _ => token(seq(':', /[^\n]+/)),

    _token: $ => choice(
      $.keyword,
      $.type_keyword,
      $.string,
      $.color,
      $.stereotype,
      $.parenthesized,
      $.separator,
      $.number,
      $.operator,
      $.punctuation,
      $.identifier,
      $.text,
    ),

    parenthesized: _ => token(seq('(', /[^)\n]*/, ')')),

    keyword: _ => token(choice(
      'as', 'is', 'also',
      'if', 'then', 'else', 'elseif', 'endif',
      'while', 'endwhile', 'repeat', 'backward',
      'fork', 'again', 'end',
      'start', 'stop', 'kill', 'detach',
      'partition', 'group', 'together',
      'package', 'namespace', 'node', 'folder',
      'frame', 'cloud', 'database', 'rectangle', 'card',
      'collections', 'queue', 'stack', 'file', 'storage',
      'hexagon', 'label', 'person', 'usecase',
      'left to right direction', 'top to bottom direction',
      'hide', 'show', 'remove',
      'allow_mixing', 'allowmixing',
      'autonumber',
      'activate', 'deactivate', 'destroy', 'create',
      'return', 'alt', 'loop', 'opt', 'par', 'break', 'critical',
      'ref', 'over',
      'box', 'end box',
      'hnote', 'rnote',
      'newpage',
      'autoactivate',
      'state',
      'title', 'header', 'footer', 'caption', 'legend',
      'endlegend', 'note', 'endnote', 'end note',
    )),

    type_keyword: _ => token(choice(
      'participant', 'actor', 'boundary', 'control', 'entity',
      'interface', 'class', 'abstract', 'annotation',
      'enum', 'component', 'object',
      'agent', 'artifact', 'map', 'struct',
    )),

    arrow: _ => token(choice(
      /[-.]+>/, /<[-.]+/, /[-.]+>>/, /<<[-.]+/,
      /[-.]*>[ox]/, /[ox]<[-.]*/, /[-.]+\\/, /\/[-.]+/,
      /<[-.]+>/, /<<[-.]+>>/,
      /[-.]+\|>/, /<\|[-.]+/,
      /[-.]+\[[^\]]*\]+[-.]*>/,
      /[-.]+o/, /o[-.]+/, /[-.]+\*/, /\*[-.]+/,
      '--', '..', '::',
    )),

    string: $ => choice(
      seq('"', repeat(choice(/[^"\\\n]+/, /\\./)), '"'),
    ),

    color: _ => token(/#[A-Fa-f0-9]{3,8}/),

    stereotype: _ => token(seq('<<', /[^>\n]*/, '>>')),

    separator: _ => token(choice('==', '||', '..', '--', '__')),

    number: _ => token(/[0-9]+/),

    operator: _ => token(choice('{', '}', '(', ')', '[', ']', '|', '#', '+', '-', '~', ',', '?', '/', '\\', '<', '>', '!')),

    punctuation: _ => token(choice(';', '=')),

    identifier: _ => token(/[A-Za-z_][A-Za-z0-9_./$]*/),

    text: _ => token(/[^\x00-\x7F]+/),

    comment: _ => token(choice(
      seq("'", /[^\n]*/),
      seq("/'", /([^']|'[^/])*/, "'/"),
    )),

    newline: _ => /\n/,
  }
});
