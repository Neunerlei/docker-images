const axios = require('axios');

const DEBIAN_RELEASE_URL = 'https://deb.debian.org/debian/dists/stable/Release';

/**
 * Fetches the current Debian stable codename from the official Release file.
 * @returns {Promise<string>} The codename (e.g. 'trixie')
 */
async function fetchStableCodename() {
    const response = await axios.get(DEBIAN_RELEASE_URL, {
        responseType: 'text',
        timeout: 15000
    });

    const match = response.data.match(/^Codename:\s*(\S+)/m);
    if (!match) {
        throw new Error('Could not parse Codename from Debian Release file');
    }

    return match[1].trim();
}

module.exports = {fetchStableCodename};
