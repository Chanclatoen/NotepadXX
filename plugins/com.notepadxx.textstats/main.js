exports.summary = function () {
  var text = notepadxx.getText();
  var words = text.split(/\s+/).filter(function (w) { return w.length > 0; }).length;
  var lines = text.length === 0 ? 0 : text.split("\n").length;
  var paragraphs = text.split(/\n\s*\n/).filter(function (p) {
    return p.trim().length > 0;
  }).length;

  notepadxx.showMessage(
    "Characters: " + text.length +
    "\nWords: " + words +
    "\nLines: " + lines +
    "\nParagraphs: " + paragraphs
  );
};

exports.removeDuplicateLines = function () {
  var seen = {}, kept = [];
  notepadxx.getText().split("\n").forEach(function (line) {
    if (!seen[line]) { seen[line] = true; kept.push(line); }
  });
  notepadxx.setText(kept.join("\n"));
};
