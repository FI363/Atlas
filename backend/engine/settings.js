const fs = require('fs');
const path = require('path');
const os = require('os');

const SETTINGS_STATE_FILE = path.join(os.homedir(), '.atlas', 'settings.json');

function loadPersistedSettings() {
  try {
    return JSON.parse(fs.readFileSync(SETTINGS_STATE_FILE, 'utf-8'));
  } catch {
    return {};
  }
}

function persistSettings(settings) {
  try {
    fs.mkdirSync(path.dirname(SETTINGS_STATE_FILE), { recursive: true });
    fs.writeFileSync(SETTINGS_STATE_FILE, JSON.stringify(settings, null, 2), 'utf-8');
  } catch (error) {
    console.error(`Could not persist Atlas settings: ${error.message}`);
  }
}

module.exports = {
  loadPersistedSettings,
  persistSettings,
  SETTINGS_STATE_FILE,
};
