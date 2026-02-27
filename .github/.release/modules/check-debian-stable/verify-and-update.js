const fs = require('fs');
const path = require('path');
const core = require('@actions/core');
const {getAllTags, parseVersionTags, buildTagFilterByArgs, buildImageNameByArgs, sortVersionList} = require('../../util/docker-version-utils');
const {findBuildPath} = require('../../util/build-matrix-generation');
const constants = require('../../util/constants');
const {escapeRegex} = require('../../util/escape-regex');

/**
 * @typedef {Object} VerificationResult
 * @property {string} sourceImage
 * @property {string} imageFilter
 * @property {boolean} passed
 * @property {string[]} buildableVersions - Versions with codename tag AND build path
 * @property {string[]} missingCodename - Versions with build path but NO codename tag
 * @property {string[]} noBuildPath - Versions without a build path (skipped)
 */

/**
 * Verifies that all buildable versions of a source image have tags for the new codename.
 * @param {import('./find-debian-aware-jobs').DebianAwareJob} job
 * @param {string} newCodename
 * @returns {Promise<VerificationResult>}
 */
async function verifyUpstreamAvailability(job, newCodename) {
    const sourceImage = buildImageNameByArgs({
        namespace: job.sourceImageNamespace,
        name: job.sourceImageName
    });

    const typeFilter = job.sourceImageType || '';
    const codenameFilter = buildTagFilterByArgs({type: typeFilter, os: newCodename});

    let buildDir = path.join(constants.SOURCE_BASE_DIR, job.targetImageName);
    if (job.targetImageType && job.targetImageType.trim() !== '') {
        buildDir = path.join(buildDir, job.targetImageType.trim());
    }

    const allTags = await getAllTags(sourceImage);
    const allVersions = parseVersionTags(allTags, job.versionPrecision, typeFilter);
    const codenameVersions = parseVersionTags(allTags, job.versionPrecision, codenameFilter);
    const latestN = sortVersionList(allVersions.keys()).slice(0, job.trackedVersions);

    const buildableVersions = [];
    const missingCodename = [];
    const noBuildPath = [];

    for (const version of latestN) {
        const buildPath = findBuildPath(buildDir, version);

        if (!buildPath) {
            noBuildPath.push(version);
            continue;
        }

        if (codenameVersions.has(version)) {
            buildableVersions.push(version);
        } else {
            missingCodename.push(version);
        }
    }

    return {
        sourceImage,
        imageFilter: codenameFilter,
        passed: missingCodename.length === 0 && buildableVersions.length > 0,
        buildableVersions,
        missingCodename,
        noBuildPath,
    };
}

/**
 * Runs upstream verification for all jobs, deduplicating identical checks.
 * @param {import('./find-debian-aware-jobs').DebianAwareJob[]} jobs
 * @param {string} newCodename
 * @returns {Promise<{verificationResults: Object<string, VerificationResult>, allVerified: boolean}>}
 */
async function verifyJobs(jobs, newCodename) {
    const verificationResults = {};
    let allVerified = true;
    const checksPerformed = new Set();

    for (const job of jobs) {
        const sourceImage = buildImageNameByArgs({
            namespace: job.sourceImageNamespace,
            name: job.sourceImageName
        });
        const imageFilter = buildTagFilterByArgs({
            type: job.sourceImageType,
            os: newCodename
        });
        const checkKey = `${sourceImage}|${newCodename}|${job.versionPrecision}|${job.trackedVersions}|${job.targetImageName}|${job.targetImageType}`;

        if (checksPerformed.has(checkKey)) {
            core.info(`  Skipping duplicate check for ${sourceImage} (filter: ${imageFilter})`);
            continue;
        }
        checksPerformed.add(checkKey);

        const jobKey = `${job.file} / ${job.jobName}`;
        core.info(`  Checking ${jobKey} → ${sourceImage} (filter: ${imageFilter})...`);

        const result = await verifyUpstreamAvailability(job, newCodename);
        verificationResults[jobKey] = result;

        if (result.passed) {
            core.info(`    ✓ ${result.buildableVersions.length} buildable: ${result.buildableVersions.join(', ')}`);
            if (result.noBuildPath.length > 0) {
                core.info(`      ${result.noBuildPath.length} skipped (no build path): ${result.noBuildPath.join(', ')}`);
            }
        } else {
            allVerified = false;
            if (result.missingCodename.length > 0) {
                core.warning(`    ✗ Awaiting codename tag: ${result.missingCodename.join(', ')}`);
            }
            if (result.buildableVersions.length === 0) {
                core.warning(`    ✗ No buildable versions found with codename '${newCodename}'`);
            }
        }
    }

    return {verificationResults, allVerified};
}

/**
 * Updates workflow files by replacing the old codename with the new one.
 * Uses targeted string replacement to preserve YAML formatting.
 * @param {import('./find-debian-aware-jobs').DebianAwareJob[]} jobs
 * @param {string} newCodename
 * @returns {string[]} List of updated file names
 */
function updateWorkflowFiles(jobs, newCodename) {
    const updatedFiles = new Set();

    const jobsByFile = new Map();
    for (const job of jobs) {
        if (!jobsByFile.has(job.filePath)) {
            jobsByFile.set(job.filePath, []);
        }
        jobsByFile.get(job.filePath).push(job);
    }

    for (const [filePath, fileJobs] of jobsByFile) {
        let content = fs.readFileSync(filePath, 'utf8');
        let modified = false;

        for (const job of fileJobs) {
            const singleQuotePattern = new RegExp(
                `(source-image-os:\\s*')${escapeRegex(job.currentOs)}(')`, 'g'
            );
            const doubleQuotePattern = new RegExp(
                `(source-image-os:\\s*")${escapeRegex(job.currentOs)}(")`, 'g'
            );

            const before = content;
            content = content
                .replace(singleQuotePattern, `$1${newCodename}$2`)
                .replace(doubleQuotePattern, `$1${newCodename}$2`);

            if (content !== before) {
                modified = true;
            }
        }

        if (modified) {
            fs.writeFileSync(filePath, content);
            updatedFiles.add(fileJobs[0].file);
        }
    }

    return Array.from(updatedFiles);
}

module.exports = {verifyJobs, updateWorkflowFiles};
