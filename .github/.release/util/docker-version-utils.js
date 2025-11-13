const axios = require('axios');
const core = require('@actions/core');
const semver = require('semver');

/**
 * This helper ensures that valid versions like "1.2", or even "4" are converted to valid semver strings
 * by appending ".0" segments as necessary.
 * @param {string} version
 * @returns {string} Valid semver string
 */
function ensureSemverValidity(version) {
    const segments = version.split('.');
    while (segments.length < 3) {
        segments.push('0');
    }
    return segments.join('.');
}

/**
 * Sorts a list of version strings in descending order (newest first)
 * @param {string[]|MapIterator<string>|SetIterator<string>} list The list of version strings
 * @return {string[]} Sorted array of version strings
 */
function sortVersionList(list) {
    return Array.from(list).sort((a, b) => semver.rcompare(semver.coerce(a), semver.coerce(b)));
}

/**
 * Sorts a list of version strings in ascending order (oldest first)
 * @param {string[]|MapIterator<string>|SetIterator<string>} list The list of version strings
 * @return {string[]} Sorted array of version strings
 */
function sortVersionListReverse(list) {
    return Array.from(list).sort((a, b) => semver.compare(semver.coerce(a), semver.coerce(b)));
}

/**
 * Compares two version strings to determine if versionA is greater than or equal to versionB
 * @param {string} versionA
 * @param {string} versionB
 * @return {boolean}
 */
function isVersionGte(versionA, versionB) {
    return semver.gte(semver.coerce(versionA), semver.coerce(versionB));
}

/**
 * Compares two version strings to determine if versionA is less than or equal to versionB
 * @param {string} versionA
 * @param {string} versionB
 * @return {boolean}
 */
function isVersionLte(versionA, versionB) {
    return semver.lte(semver.coerce(versionA), semver.coerce(versionB));
}

/**
 * Request authentication header for Docker Registry
 * @param {AxiosResponse} response
 * @return {Promise<{Authorization: string}>}
 */
async function requestAuthHeader(response) {
    function extractAuthValue(field, wwwAuthHeader) {
        const regex = new RegExp(`${field}="([^"]+)"`);
        const match = wwwAuthHeader.match(regex);
        return match ? match[1] : '';
    }

    const wwwAuth = response.headers['www-authenticate'];
    if (!wwwAuth) {
        throw new Error('WWW-Authenticate header not found in 401 response');
    }

    const authParams = wwwAuth.replace('Bearer ', '');
    const realm = extractAuthValue('realm', authParams);
    const service = extractAuthValue('service', authParams);
    const scope = extractAuthValue('scope', authParams);

    if (!realm) {
        throw new Error('Authentication realm not found in WWW-Authenticate header');
    }

    const tokenResponse = await axios.get(realm, {
        params: {service, scope}
    });

    if (!tokenResponse.data || !tokenResponse.data.token) {
        throw new Error('Failed to obtain authentication token');
    }

    return {
        'Authorization': `Bearer ${tokenResponse.data.token}`
    };
}

/**
 * Get all tags for a Docker image from Docker Hub
 * @param {string} image - The fully qualified image name (e.g., 'library/nginx')
 * @returns {Promise<string[]>} Array of tag names
 */
async function getAllTags(image) {
    let nextUri = `https://index.docker.io/v2/${image}/tags/list`;
    const allTags = [];

    while (nextUri) {
        try {
            // First request to get auth requirements
            let authHeader = {};

            const initialResponse = await axios.get(nextUri, {
                validateStatus: (status) => status === 401 || status === 200
            });

            if (initialResponse.status === 401) {
                authHeader = await requestAuthHeader(initialResponse);
            }

            // Get the actual tags
            const response = await axios.get(nextUri, {
                headers: authHeader,
                validateStatus: (status) => status < 500
            });

            if (response.data && response.data.tags) {
                allTags.push(...response.data.tags);
            }

            // Check for pagination
            const linkHeader = response.headers['link'];
            if (linkHeader && linkHeader.includes('rel="next"')) {
                const match = linkHeader.match(/<([^>]+)>/);
                if (match) {
                    nextUri = `https://index.docker.io${match[1]}`;
                } else {
                    nextUri = null;
                }
            } else {
                nextUri = null;
            }
        } catch (error) {
            console.error(`Error fetching tags: ${error.message}`);
            core.setFailed(`Error fetching tags: ${error.message}`);
            throw error;
        }
    }

    return allTags;
}

/**
 * Receives a list of Docker tags and extracts unique version numbers.
 *
 * @param {string[]} tags Array of Docker tag strings
 * @param {number} precision Number of version segments to consider (1-3), default 3
 * @param {string} filter Optional filter for variant (e.g., 'alpine'), a type suffix to match
 *
 * @returns {Map<string,string>} A map of version strings to original tags
 */
function parseVersionTags(tags, precision = 3, filter = '') {
    const versions = new Map();

    // Build version pattern based on precision
    let versionPattern;
    if (precision === 1) {
        versionPattern = /^(\d+)$/;
    } else if (precision === 2) {
        versionPattern = /^(\d+)\.(\d+)$/;
    } else {
        versionPattern = /^(\d+)\.(\d+)\.(\d+)$/;
    }

    for (const tag of tags) {
        let version = tag;

        // Apply filter if provided
        if (filter) {
            if(!tag.endsWith(`-${filter}`)){
                continue;
            }
            version = tag.replace(new RegExp(`-${filter}$`), '');
        }

        // Match version pattern
        const match = version.match(versionPattern);
        if (match) {
            versions.set(match[0], tag);
        }
    }

    return versions;
}

module.exports = {
    getAllTags,
    parseVersionTags,
    sortVersionList,
    sortVersionListReverse,
    isVersionGte,
    isVersionLte
};
