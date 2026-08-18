function parseCurrent() {
  return JSON.parse(notepadxx.getText());
}

exports.format = function () {
  try {
    notepadxx.setText(JSON.stringify(parseCurrent(), null, 2));
  } catch (e) {
    notepadxx.showMessage("Not valid JSON: " + e.message);
  }
};

exports.minify = function () {
  try {
    notepadxx.setText(JSON.stringify(parseCurrent()));
  } catch (e) {
    notepadxx.showMessage("Not valid JSON: " + e.message);
  }
};

exports.validate = function () {
  try {
    parseCurrent();
    notepadxx.showMessage("Valid JSON");
  } catch (e) {
    notepadxx.showMessage("Invalid JSON: " + e.message);
  }
};
