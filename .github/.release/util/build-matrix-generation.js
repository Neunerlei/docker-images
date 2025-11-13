const fs = require('fs');
const semver = require('semver');
const path = require('path');
const core = require('@actions/core');
const constants = require('./constants');
const {ensureSemverValidity, sortVersionList, sortVersionListReverse, isVersionLte, isVersionGte} = require('./docker-version-utils');

/*
* Helper function for Semver-aware directory selection
* Returns an empty string if no suitable directory is found
* @param {string} sourceBaseDir - The base directory to search in
* @param {string} targetVersion - The target version to match
* @returns {string} The path to the best matching directory, or empty string if none found
*/
function findBuildPath(baseDir, targetVersion) {
    let bestMatchDir = '';

    if (!fs.existsSync(baseDir)) {
        console.log(`Base directory does not exist: ${baseDir}`);
        return null;
    }

    // Get all directories in the base directory
    const entries = fs.readdirSync(baseDir, { withFileTypes: true });
    const availableDirs = entries
        .filter(entry => entry.isDirectory())
        .map(entry => entry.name);

    // Sort in descending order
    const sortedDirs = sortVersionList(availableDirs);

    // Find the best match
    for (const dirVersion of sortedDirs) {
        if(isVersionLte(dirVersion, targetVersion)) {
            bestMatchDir = dirVersion;
            // Since the list is sorted descending, the first match is the best one
            break;
        }
    }

    if (!bestMatchDir) {
        return null;
    }

    return path.join(baseDir, bestMatchDir);
}

/**
 * Get the latest N versions from a list
 * @param {Map<string,string>} versions A map of version numbers to their docker tags
 * @param {number} take Number of latest versions to return
 * @return {string[]} Array of version strings where the oldest comes first, the latest last
 */
function getLatestVersions(versions, take) {
    return sortVersionListReverse(sortVersionList(versions.keys()).slice(0, take))
}

/**
 * Generates a build matrix for CI/CD pipelines
 * @param {Object} options Options object
 * @param {string} options.sourceImage Fully qualified source image name (e.g. library/nginx)
 * @param {string} options.targetImageName Target image name (e.g. nginx)
 * @param {string} [options.targetImageType] Target image type (e.g., 'alpine', 'slim', etc.)
 * @param {boolean} options.detectLatestVersion Whether to mark the latest version in the matrix
 * @param {Map<string,string>} options.sourceVersions Map of version numbers of the source image to their docker tags
 * @param {number} [options.trackedVersions=3] Number of latest versions to include in the matrix
 * @param {string|undefined} [options.lastVersion] Last version to build (for deprecation purposes). Can be set to a version that will be the last to build.
 *                                       Even if newer versions are discovered, they will not be built.
 *                                       If the given version is not found, no build will be performed. This must be in the format matching the precision.
 * @return {{include: {version: string, tag: string, sourceImageWithTag: string, buildPath: string, isLatest: boolean}[]}|null} Build matrix object, null if no versions found
 */
function generateBuildMatrix(options) {
    const {
        sourceImage,
        sourceVersions,
        targetImageName,
        targetImageType,
        detectLatestVersion,
        trackedVersions = 3,
        lastVersion
    } = options;

    if(!sourceImage){
        core.setFailed('Source image must be specified to generate build matrix');
        return null;
    }

    if(sourceVersions.size === 0){
        core.setFailed('No versions available to generate build matrix');
        return null;
    }

    core.info(`Generating build matrix with trackedVersions=${trackedVersions}, lastVersion=${lastVersion || 'not set'} of ${sourceVersions.size} available versions`);

    let versionsToBuild = getLatestVersions(sourceVersions, trackedVersions);

    if(lastVersion){
        if(!versionsToBuild.includes(lastVersion)){
            // We need to make sure that the "last version" is smaller than the greatest discovered version
            const greatestDiscoveredVersion = sortVersionList(versionsToBuild)[0];

            if(isVersionGte(lastVersion, greatestDiscoveredVersion)) {
                core.info(`The specified last version ${lastVersion} is greater than or equal to the greatest discovered version ${greatestDiscoveredVersion}. All discovered versions will be built.`);
                // No filtering needed
            } else {
                // No matching last version found, no build will be performed
                core.warning(`The specified last version ${lastVersion} was not found among the discovered versions. No build will be performed.`);
                return null;
            }
        } else {
            // Filter the versions to only include up to and including the last version
            const filteredVersions = [];
            for(const version of versionsToBuild){
                filteredVersions.push(version);
                if(version === lastVersion){
                    break;
                }
            }
            versionsToBuild = filteredVersions;
        }
    }

    if(versionsToBuild.length === 0){
        core.warning('No versions to build after applying filters');
        return null;
    }

    const buildMatrix = {include:[]};

    let baseDir = path.join(constants.SOURCE_BASE_DIR, targetImageName);
    if(targetImageType && targetImageType.trim() !== ''){
        baseDir = path.join(baseDir, targetImageType.trim());
        core.info(`Using target image type sub-directory: ${targetImageType.trim()}`);
    }

    for(const version of versionsToBuild){
        const buildPath = findBuildPath(baseDir, version);
        if(!buildPath){
            core.info(`No build path found for version ${version} in base dir ${baseDir}, skipping...`);
            continue;
        }
        let tag = version;
        if(targetImageType && targetImageType.trim() !== ''){
            tag = `${version}-${targetImageType.trim()}`;
        }
        buildMatrix.include.push({
            version: version,
            tag,
            sourceImageWithTag: `${sourceImage}:${sourceVersions.get(version)}`,
            buildPath: buildPath,
            isLatest: false
        });
    }

    if(buildMatrix.include.length === 0){
        core.warning('No valid build paths found for any versions to build');
        return null;
    }

    if(detectLatestVersion){
        const latestVersion = buildMatrix.include[buildMatrix.include.length - 1];
        if(latestVersion){
            core.info(`Marking version ${latestVersion.version} as latest in the build matrix`);
            latestVersion.isLatest = true;
        }
    }

    return buildMatrix;
}

module.exports = {
    generateBuildMatrix
};
