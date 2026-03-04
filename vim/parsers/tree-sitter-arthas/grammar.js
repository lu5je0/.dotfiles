module.exports = grammar({
  name: 'arthas',

  extras: $ => [/[ \t\f\r]/],

  rules: {
    source_file: $ => seq(
      repeat(choice(seq($._line_content, $.newline), $.newline)),
      optional($._line_content)
    ),

    _line_content: $ => choice(
      $.comment,
      seq($.command, repeat($.argument), optional($.comment)),
      seq($.argument, repeat($.argument), optional($.comment))
    ),

    argument: $ => choice(
      $.option,
      $.class_name,
      $.method_name,
      $.string,
      $.ognl_expr,
      $.wildcard,
      $.identifier,
      $.number
    ),

    command: _ => choice(
      'dashboard', 'thread', 'jad', 'classloader', 'sc', 'sm',
      'watch', 'trace', 'monitor', 'tt',
      'ognl', 'getstatic', 'vmtool', 'heapdump',
      'sysprop', 'sysenv', 'logger',
      'stop', 'reset', 'version', 'help', 'cls', 'clear',
      'cat', 'pwd', 'session', 'jobs', 'kill'
    ),

    option: _ => token(choice(
      /--[A-Za-z][A-Za-z0-9-]*/,
      '--',
      /-[A-Za-z]+/
    )),

    class_name: _ => token(/[A-Z][a-zA-Z0-9_]*(\.[A-Za-z0-9_]+)*/),

    method_name: _ => token(/[a-z][a-zA-Z0-9_]*/),

    identifier: _ => token(/[A-Za-z_.$][A-Za-z0-9_.$-]*/),

    number: _ => token(/[0-9]+/),

    string: $ => choice(
      seq('"', repeat(choice(/[^"\\\n]+/, /\\./)), '"'),
      seq("'", repeat(choice(/[^'\\\n]+/, /\\./)), "'")
    ),

    ognl_expr: _ => token(seq('{', /[^}\n]*/, '}')),

    wildcard: _ => token(/[?*]+/),

    comment: _ => token(seq('//', /[^\n]*/)),

    newline: _ => /\n/
  }
});
