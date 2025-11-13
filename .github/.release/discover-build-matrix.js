const core = require('@actions/core');
const {getAllTags, parseVersionTags} = require('.//util/docker-version-utils');
const {generateBuildMatrix} = require('.//util/build-matrix-generation');
const constants = require('.//util/constants');
const path = require('node:path');
const semver = require('semver');

// Use inputs defined in the workflow file
/**
 * The name of the image to build (e.g. nginx) (This relates to the folder structure in src/)
 * @type {string}
 */
const targetImageNameInput = core.getInput('image-name', {required: true});
/**
 * The type of the image to build (e.g. fpm-debian) (This relates to the sub-folder structure in src/your-image/)
 * @type {string}
 */
const targetImageTypeInput = core.getInput('image-type');
/**
 * The namespace of the source image to discover versions from (e.g. library)
 * @type {string}
 */
const sourceImageNamespaceInput = core.getInput('source-image-namespace', {required: true});
/**
 * The name of the source image to discover versions from (e.g. nginx)
 * @type {string}
 */
const sourceImageNameInput = core.getInput('source-image-name', {required: true});
/**
 * Allows for filtering the tags for a certain type (e.g. "alpine" to get only alpine variants)
 * When using this, we assume the image tags are structured like: "1.23.4-alpine", "1.23.4-fpm-alpine", etc.
 * @type {string}
 */
const sourceImageTypeInput = core.getInput('source-image-type');
/**
 * Number of most recent versions to track/build (default: 3)
 * @type {string}
 */
const trackedVersionsInput = core.getInput('tracked-versions');
/**
 * If this flag is set, it is expected that it is set to the last version to build before deprecating the image.
 * While the version set in this flag is present in the "tracked-versions", it will be built as usual.
 * Once the version is no longer in the tracked versions (because newer versions exist),
 * there will no longer any build performed. This allows for a graceful deprecation of images.
 * As soon as the flag is set, the deprecation notice will be shown in the generated tags list.
 * @type {string}
 */
const deprecatedInput = core.getInput('deprecated');
/**
 * Number of version segments to consider when discovering versions (e.g., 2 for major.minor), default is 3 (major.minor.patch)
 * This allows you to decide if you want to build every patch version or just the latest patch of each minor version.
 * @type {string}
 */
const versionPrecisionInput = core.getInput('version-precision');
/**
 * If set to true, the image built for the latest version in the "tracked-versions" will also be tagged as "latest" and pushed.
 * @type {boolean}
 */
const detectLatestVersion = core.getBooleanInput('latest-tag') || false;

const sourceImage = `${sourceImageNamespaceInput}/${sourceImageNameInput}`;
const targetImage = `${constants.IMAGE_NAMESPACE}/${targetImageNameInput}`;
core.info(`Starting build matrix discovery for image: ${targetImage} based on source image: ${sourceImage}`);

core.info(`Discovering available tags...`);
const [allSourceTags, allTargetImageTags] = await Promise.all([
    getAllTags(sourceImage),
    getAllTags(targetImage)
]);

const precision = (versionPrecisionInput && !isNaN(parseInt(versionPrecisionInput, 10))) ? parseInt(versionPrecisionInput, 10) : 3;
core.info(`Using version precision: ${precision}`);

core.info(`Discovered ${allSourceTags.length} tags for source image ${sourceImage}`);
const sourceVersions = parseVersionTags(allSourceTags, precision, sourceImageTypeInput);
core.info(`Parsed ${sourceVersions.size} unique versions from source image tags`);

core.info(`There are currently ${allTargetImageTags.length} tags for target image ${targetImage}`);
const targetVersions = parseVersionTags(allTargetImageTags, precision, targetImageTypeInput);
core.info(`Parsed ${targetVersions.size} unique versions from target image tags`);

const trackedVersions = (trackedVersionsInput && !isNaN(parseInt(trackedVersionsInput, 10))) ? parseInt(trackedVersionsInput, 10) : 3;
core.info(`Tracking the latest ${trackedVersions} versions for building`);

let lastVersion = deprecatedInput && deprecatedInput.trim() !== '' ? deprecatedInput.trim() : undefined;
let deprecated = false;
if (lastVersion) {
    deprecated = true;
    core.info(`Deprecation mode enabled. Last version to build: ${lastVersion}`);
}

const buildMatrix = generateBuildMatrix({
    sourceImage,
    sourceVersions,
    targetImageName: targetImageNameInput,
    targetImageType: targetImageTypeInput,
    detectLatestVersion,
    trackedVersions,
    lastVersion
});

const maintainedTags = [];
const allTags = new Set(Array.from(targetVersions.keys()));

const buildNeeded = buildMatrix !== null;
if (buildNeeded) {
    core.info(`Build matrix generated with ${buildMatrix.include.length} entries:`);
    for (const entry of buildMatrix.include) {
        core.info(` - Version: ${entry.version}, Tag: ${entry.tag}, Source Image: ${entry.sourceImageWithTag}, Build Path: ${entry.buildPath}, Is Latest: ${entry.isLatest}`);
        allTags.add(entry.tag);
        maintainedTags.push(entry.tag);
    }
} else {
    core.info('No builds needed based on the discovered versions and deprecation settings.');
}

/**
 * The build matrix object to be used in the build step
 * The matrix looks like: {include: {version: string, tag: string, sourceImageWithTag: string, buildPath: string, isLatest: boolean}[]}
 */
core.setOutput('build-matrix', JSON.stringify(buildMatrix ?? {include: []}));
/**
 * Indicates if a build is needed based on the discovered versions and deprecation settings
 */
core.setOutput('build-needed', buildNeeded);
/**
 * The name of the image to build (e.g. neunerlei/nginx)
 */
core.setOutput('image', targetImage);
/**
 * The name of the image to build with type (e.g. neunerlei/nginx (fpm-debian))
 */
core.setOutput('image-name', `${targetImage}${targetImageTypeInput && targetImageTypeInput.trim() !== '' ? ` (${targetImageTypeInput.trim()})` : ''}`);
/**
 * A comma-separated list of all maintained tags, this is required for the build-tag-list.js file
 */
core.setOutput('tag-list-maintained', Array.from(maintainedTags).join(','));
/**
 * A comma-separated list of all discovered tags, this is required for the build-tag-list.js file
 */
core.setOutput('tag-list-all', Array.from(allTags).join(','));
/**
 * Indicates if the image is deprecated, this is required for the build-tag-list.js file
 */
core.setOutput('deprecated', deprecated);
