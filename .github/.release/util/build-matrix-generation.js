const fs = require('fs');
const semver = require('semver');
const path = require('path');
const core = require('@actions/core');
const constants = require('./constants');
const {ensureSemverValidity, sortVersionList, sortVersionListReverse, isVersionLte, isVersionGte, toRollingVersion} = require('./docker-version-utils');

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
 * Selects the versions to build, based on the tracked version limits.
 *
 * When all versions are patch versions (3 segments, e.g. "3.13.8"), the versions are grouped
 * by their version line ("3.13"). The newest "trackedPatchVersions" patches of the newest
 * "trackedVersions" lines get selected. So with trackedVersions=2 and trackedPatchVersions=2
 * out of ["3.12.1", "3.12.9", "3.13.4", "3.13.8"] the result is
 * ["3.12.1", "3.12.9", "3.13.4", "3.13.8"], while out of ["3.12.1", "3.13.4", "3.13.8", "3.14.2"]
 * only ["3.13.4", "3.13.8", "3.14.2"] remains (the 3.12 line is no longer tracked).
 *
 * For versions with less than 3 segments (e.g. "3.13"), the behavior stays as it was:
 * the newest "trackedVersions" versions get selected.
 *
 * @param {Map<string,string>} versions A map of version numbers of the source image to their docker tags
 * @param {number} trackedVersions Number of version lines to track
 * @param {number} trackedPatchVersions Number of latest patch versions to build per version line
 * @return {string[]} Array of version strings, oldest first, latest last
 */
function selectVersionsToBuild(versions, trackedVersions, trackedPatchVersions) {
    const sortedVersions = sortVersionList(versions.keys());
    if (sortedVersions.length === 0 || !sortedVersions.every(version => version.split('.').length === 3)) {
        return getLatestVersions(versions, trackedVersions);
    }

    const patchesByLine = new Map();
    for (const version of sortedVersions) {
        const line = toRollingVersion(version);
        if (!patchesByLine.has(line)) {
            patchesByLine.set(line, []);
        }
        patchesByLine.get(line).push(version);
    }

    const trackedLines = sortVersionList(patchesByLine.keys()).slice(0, trackedVersions);
    const selectedVersions = [];
    for (const line of trackedLines) {
        selectedVersions.push(...patchesByLine.get(line).slice(0, Math.max(1, trackedPatchVersions)));
    }

    return sortVersionListReverse(selectedVersions);
}

/**
 * Generates a build matrix for CI/CD pipelines
 * @param {Object} options Options object
 * @param {string} options.sourceImage Fully qualified source image name (e.g. library/nginx)
 * @param {string} options.targetImageName Target image name (e.g. nginx)
 * @param {string} [options.targetImageType] Target image type (e.g., 'alpine', 'slim', etc.)
 * @param {boolean} options.detectLatestVersion Whether to mark the latest version in the matrix
 * @param {Map<string,string>} options.sourceVersions Map of version numbers of the source image to their docker tags
 * @param {number} [options.trackedVersions=3] Number of latest version lines (minor versions) to include in the matrix
 * @param {number} [options.trackedPatchVersions=1] Number of latest patch versions to build per version line.
 *                                       Only used when the discovered versions are patch versions (version precision 3),
 *                                       otherwise it is ignored.
 * @param {boolean} [options.rollingTags=true] Whether each version line should additionally receive a "rolling" tag
 *                                       (e.g. "3.13" pointing to the newest built "3.13.x" patch).
 *                                       Only used when the discovered versions are patch versions (version precision 3).
 * @param {string|undefined} [options.lastVersion] Last version to build (for deprecation purposes). Can be set to a version that will be the last to build.
 *                                       Even if newer versions are discovered, they will not be built.
 *                                       If the given version is not found, no build will be performed. This must be in the format matching the precision.
 * @return {{include: {version: string, tag: string, rollingTag: string, sourceImageWithTag: string, buildPath: string, isLatest: boolean}[]}|null} Build matrix object, null if no versions found.
 *                                       The "rollingTag" is empty when no rolling tag applies to the entry.
 *                                       A rolling/latest tag is only ever attached to the newest DISCOVERED
 *                                       version (of its line / overall): a deprecation cutoff that stops the
 *                                       selection below the newest upstream patch must not re-point tags that
 *                                       already published builds hold, so the entry simply carries no
 *                                       rollingTag and is not marked isLatest.
 */
function generateBuildMatrix(options) {
    const {
        sourceImage,
        sourceVersions,
        targetImageName,
        targetImageType,
        detectLatestVersion,
        trackedVersions = 3,
        trackedPatchVersions = 1,
        rollingTags = true,
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

    core.info(`Generating build matrix with trackedVersions=${trackedVersions}, trackedPatchVersions=${trackedPatchVersions}, rollingTags=${rollingTags}, lastVersion=${lastVersion || 'not set'} of ${sourceVersions.size} available versions`);

    let versionsToBuild = selectVersionsToBuild(sourceVersions, trackedVersions, trackedPatchVersions);

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

    // The newest DISCOVERED version overall, and the newest discovered patch per
    // version line — computed from the FULL discovered set (sourceVersions), not
    // from versionsToBuild. Rolling tags and "latest" must never map to an older
    // version than what earlier runs already published: a deprecation cutoff
    // deliberately stops BUILDING newer patches, but those newer patches exist
    // upstream and, once published, own the registry's rolling tag and "latest".
    // Re-pointing them at the truncated tip (e.g. pushing 8.2 -> 8.2.4 while
    // 8.2.8 is already published) would move every consumer BACKWARD. The cutoff
    // must freeze the build set, not drag the pointers — so truncated entries
    // simply carry no rollingTag and are not marked isLatest, leaving the
    // already-published pointers untouched.
    const discoveredSorted = sortVersionList(sourceVersions.keys());
    const newestDiscoveredVersion = discoveredSorted[0] || '';
    const newestPatchByLine = new Map();
    for(const version of discoveredSorted){
        if(version.split('.').length !== 3) continue;
        const line = toRollingVersion(version);
        // Discovered versions arrive sorted descending, so the FIRST patch seen
        // per line is the newest one — exactly the findBuildPath idiom.
        if(!newestPatchByLine.has(line)){
            newestPatchByLine.set(line, version);
        }
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
        let rollingTag = '';
        if(targetImageType && targetImageType.trim() !== ''){
            tag = `${version}-${targetImageType.trim()}`;
        }
        // Rolling tags only apply to patch versions (3 segments), e.g. "3.13.8" -> "3.13",
        // and only to the newest DISCOVERED patch of the line (see newestPatchByLine):
        // when a deprecation cutoff truncates the line below its newest patch, the
        // truncated tip builds with its concrete tag only, so the registry's rolling
        // pointer stays where the already-published newer patch left it.
        if(rollingTags && version.split('.').length === 3){
            if(newestPatchByLine.get(toRollingVersion(version)) === version){
                rollingTag = toRollingVersion(version);
                if(targetImageType && targetImageType.trim() !== ''){
                    rollingTag = `${rollingTag}-${targetImageType.trim()}`;
                }
            }
        }
        buildMatrix.include.push({
            version: version,
            tag,
            rollingTag,
            sourceImageWithTag: `${sourceImage}:${sourceVersions.get(version)}`,
            buildPath: buildPath,
            isLatest: false
        });
    }

    if(buildMatrix.include.length === 0){
        core.warning('No valid build paths found for any versions to build');
        return null;
    }

    // The rollingTag gate above admits at most one entry per version line (the
    // newest discovered patch), so the rolling tag always points to the newest
    // BUILT patch of its line as well — no per-line dedupe pass is needed.

    if(detectLatestVersion){
        const latestVersion = buildMatrix.include[buildMatrix.include.length - 1];
        // "latest" must not move backward either: only the newest DISCOVERED
        // version may carry it. When a deprecation cutoff stops the selection at
        // an older tip, the registry's "latest" stays where the already-published
        // newer version left it (see newestPatchByLine above).
        if(latestVersion && latestVersion.version === newestDiscoveredVersion){
            core.info(`Marking version ${latestVersion.version} as latest in the build matrix`);
            latestVersion.isLatest = true;
        }
    }

    return buildMatrix;
}

module.exports = {
    generateBuildMatrix,
    findBuildPath,
    selectVersionsToBuild
};
