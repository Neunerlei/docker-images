/**
 * Escapes special characters in a string for use in a regular expression.
 * @param {string} str
 * @returns {string}
 */
function escapeRegex(str) {
    return str.replace(/[/\-\\^$*+?.()|[\]{}]/g, '\\$&');
}

module.exports = {escapeRegex};
