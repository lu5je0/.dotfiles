function! edit#CountSelectionRegion() abort
  call feedkeys("gvg\<c-g>\<Esc>", 'ti')
endfunction
