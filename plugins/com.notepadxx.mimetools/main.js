// JavaScriptCore has no atob/btoa, so Base64 is implemented directly.
var ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function selectionOrAll() {
  var sel = notepadxx.getSelection();
  if (sel.length > 0) {
    return notepadxx.getText().substr(sel.location, sel.length);
  }
  return notepadxx.getText();
}

function replace(text) {
  var sel = notepadxx.getSelection();
  if (sel.length > 0) {
    notepadxx.replaceSelection(text);
  } else {
    notepadxx.setText(text);
  }
}

function encode64(input) {
  var out = "", i = 0;
  while (i < input.length) {
    var c1 = input.charCodeAt(i++), c2 = input.charCodeAt(i++), c3 = input.charCodeAt(i++);
    out += ALPHABET.charAt(c1 >> 2);
    out += ALPHABET.charAt(((c1 & 3) << 4) | (isNaN(c2) ? 0 : c2 >> 4));
    out += isNaN(c2) ? "=" : ALPHABET.charAt(((c2 & 15) << 2) | (isNaN(c3) ? 0 : c3 >> 6));
    out += isNaN(c3) ? "=" : ALPHABET.charAt(c3 & 63);
  }
  return out;
}

function decode64(input) {
  var clean = input.replace(/[^A-Za-z0-9+/=]/g, ""), out = "", i = 0;
  while (i < clean.length) {
    var e1 = ALPHABET.indexOf(clean.charAt(i++)), e2 = ALPHABET.indexOf(clean.charAt(i++));
    var e3 = ALPHABET.indexOf(clean.charAt(i++)), e4 = ALPHABET.indexOf(clean.charAt(i++));
    out += String.fromCharCode((e1 << 2) | (e2 >> 4));
    if (e3 !== 64 && e3 !== -1) out += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
    if (e4 !== 64 && e4 !== -1) out += String.fromCharCode(((e3 & 3) << 6) | e4);
  }
  return out;
}

exports.base64Encode = function () { replace(encode64(selectionOrAll())); };
exports.base64Decode = function () { replace(decode64(selectionOrAll())); };
exports.urlEncode = function () { replace(encodeURIComponent(selectionOrAll())); };
exports.urlDecode = function () { replace(decodeURIComponent(selectionOrAll())); };
