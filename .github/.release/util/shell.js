const core = require('@actions/core');
const child_process = require('child_process');

/**
 * Executes a shell command, logs it, and returns trimmed stdout.
 * Throws on non-zero exit.
 * @param {string} command
 * @returns {string}
 */
function run(command) {
    core.info(`$ ${command}`);
    return child_process.execSync(command, {
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
    }).trim();
}

/**
 * Like run(), but returns empty string instead of throwing on failure.
 * @param {string} command
 * @returns {string}
 */
function runSafe(command) {
    try {
        return run(command);
    } catch (e) {
        core.warning(`Command failed (non-fatal): ${command}`);
        if (e.stderr) core.warning(e.stderr.toString().trim());
        return '';
    }
}

module.exports = {run, runSafe};
