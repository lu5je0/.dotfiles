-- Compatibility shim: existing call sites and tests `require` the
-- `sources.files` module. The actual implementation now lives in
-- `sources.files.init`.
return require('lu5je0.ext.tree-sidebar.sources.files.init')
