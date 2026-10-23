window.isOnWindowHtml = true;
window._options = { userLocale: 'zh-Hans', locale: 'zh-Hans', sendAnonymousUsage: false, enableAutoSave: false, spellcheck: false, noPairingMatch: false };
window._doc = {};
window.reqnode = undefined;
window.require = undefined;
window.JSBridge = {
  invoke: async () => null,
  invokeSync: () => null,
  showInBrowser: () => {},
  putSetting: (key, value) => { window._options[key] = value; },
  menu: { update: () => {} },
};
window.bridge = {
  callSync: method => method === 'clipboard.readText' ? (window.springNoteClipboardText || '') : null,
  callHandler: (method, args, callback) => { if (typeof callback === 'function') callback({}); },
  registerHandler: () => {},
};
for (const method of ['sendError', 'sendLog', 'sendLogForDebug']) console[method] = (...args) => console.debug(method, ...args);
window.requestSmartSchedule = (fn, delay) => setTimeout(fn, delay);
window.cancelSmartSchedule = clearTimeout;
