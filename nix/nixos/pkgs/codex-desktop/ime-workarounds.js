// WeTypeX 的 preedit_cursor_at_beginning 策略要求首段组字的光标也留在起点。
function codexImePredictionPlugin(plugin) {
  const originalView = plugin.spec.view;
  const handlers = plugin.props.handleDOMEvents;
  const originalStart = handlers.compositionstart;
  const originalEnd = handlers.compositionend;
  let pendingCaret = null;

  handlers.compositionstart = function (view, event) {
    pendingCaret = view.dom.querySelector("[data-cumberbatch]")
      ? view.state.selection.head
      : null;
    const prediction = plugin.getState(view.state);
    // GNOME 的输入法链路可能直接发 compositionstart，没有 keyCode=229 的 keydown。
    if (prediction && !prediction.hiddenForComposition) {
      view.dispatch(view.state.tr.setMeta("cumberbatch-composition", true));
    }
    return originalStart?.call(this, view, event) ?? false;
  };
  handlers.compositionend = function (view, event) {
    pendingCaret = null;
    return originalEnd?.call(this, view, event) ?? false;
  };

  plugin.spec.view = function (view) {
    const inner = originalView?.(view);
    const input = (event) => {
      if (
        pendingCaret == null ||
        !event.isComposing ||
        event.inputType !== "insertCompositionText"
      ) return;
      const position = pendingCaret;
      pendingCaret = null;
      // 先同步真实 preedit，再校正隐藏预测导致的首段光标偏移；不改输入正文。
      view.domObserver.flush();
      if (
        view.composing &&
        view.state.selection.head !== position &&
        position <= view.state.doc.content.size
      ) {
        view.dispatch(view.state.tr.setSelection(
          view.state.selection.constructor.create(view.state.doc, position),
        ));
      }
    };
    view.dom.addEventListener("input", input, true);
    return {
      update(...args) {
        inner?.update?.apply(inner, args);
      },
      destroy() {
        pendingCaret = null;
        view.dom.removeEventListener("input", input, true);
        inner?.destroy?.();
      },
    };
  };
  return plugin;
}

function codexImeFocus(view) {
  view.focus();
  const dom = view.dom;
  const doc = dom.ownerDocument;
  const win = doc.defaultView;
  if (!win) return;
  const requests = codexImeFocus.requests ??= new WeakMap();
  const pending = requests.get(view);
  if (pending != null) {
    win.cancelAnimationFrame(pending);
    requests.delete(view);
  }
  // 发送后的过渡层仍带 inert 时，浏览器会忽略 focus()，首键便会漏过输入法。
  if (view.isDestroyed || !dom.closest("[inert]") || doc.activeElement !== doc.body) return;
  const deadline = win.performance.now() + 2000;
  function retry() {
    requests.delete(view);
    if (
      view.isDestroyed ||
      !dom.isConnected ||
      doc.activeElement !== doc.body ||
      win.performance.now() > deadline
    ) return;
    if (dom.closest("[inert]")) {
      requests.set(view, win.requestAnimationFrame(retry));
      return;
    }
    if (dom.closest("[hidden], [aria-hidden=true]") || !dom.getClientRects().length) return;
    view.focus();
  }
  requests.set(view, win.requestAnimationFrame(retry));
}
