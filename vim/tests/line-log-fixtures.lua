return {
  {
    name = 'rename_chain_tracks_old_path',
    file = 'b.txt',
    start_line = 2,
    end_line = 2,
    commits = {
      {
        id = 'add_a',
        message = 'add a',
        writes = {
          ['a.txt'] = 'one\ntwo\nthree\n',
        },
      },
      {
        id = 'edit_a',
        message = 'edit a',
        writes = {
          ['a.txt'] = 'one\nTWO\nthree\n',
        },
      },
      {
        id = 'rename_to_b',
        message = 'rename to b',
        rename = { from = 'a.txt', to = 'b.txt' },
      },
      {
        id = 'edit_b',
        message = 'edit b',
        writes = {
          ['b.txt'] = 'one\nTWO!\nthree\n',
        },
      },
    },
    expected_revisions = {
      { id = 'edit_b', file = 'b.txt' },
      { id = 'rename_to_b', file = 'b.txt' },
      { id = 'edit_a', file = 'a.txt' },
      { id = 'add_a', file = 'a.txt' },
    },
    expected_commits = { 'edit_b', 'edit_a', 'add_a' },
  },
  {
    name = 'block_stops_when_history_runs_out',
    file = 'notes.txt',
    start_line = 3,
    end_line = 3,
    commits = {
      {
        id = 'add_base',
        message = 'add base',
        writes = {
          ['notes.txt'] = 'alpha\nbeta\n',
        },
      },
      {
        id = 'add_tail',
        message = 'add tail',
        writes = {
          ['notes.txt'] = 'alpha\nbeta\ngamma\n',
        },
      },
      {
        id = 'edit_tail',
        message = 'edit tail',
        writes = {
          ['notes.txt'] = 'alpha\nbeta\nGAMMA\n',
        },
      },
    },
    expected_revisions = {
      { id = 'edit_tail', file = 'notes.txt' },
      { id = 'add_tail', file = 'notes.txt' },
      { id = 'add_base', file = 'notes.txt' },
    },
    expected_commits = { 'edit_tail', 'add_tail' },
  },
}
