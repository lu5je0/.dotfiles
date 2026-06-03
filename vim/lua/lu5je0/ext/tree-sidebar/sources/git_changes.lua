-- Compatibility shim: existing call sites and tests `require` the
-- `sources.git_changes` module. The implementation now lives under
-- `sources.git_changes.init`.
return require('lu5je0.ext.tree-sidebar.sources.git_changes.init')
