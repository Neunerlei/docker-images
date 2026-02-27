const fs = require('fs');
const path = require('path');
const core = require('@actions/core');
const yaml = require('yaml');

/**
 * @typedef {Object} DebianAwareJob
 * @property {string} file - Workflow filename
 * @property {string} filePath - Absolute path to workflow file
 * @property {string} jobName - Job key within the workflow
 * @property {string} currentOs - Currently configured OS codename
 * @property {string} sourceImageNamespace
 * @property {string} sourceImageName
 * @property {string} sourceImageType
 * @property {string} targetImageName
 * @property {string} targetImageType
 * @property {number} trackedVersions
 * @property {number} versionPrecision
 */

/**
 * Scans workflow files for jobs that use the build engine with source-image-os set.
 * @param {string} workflowsDir Absolute path to the workflows directory
 * @returns {DebianAwareJob[]}
 */
function findDebianAwareJobs(workflowsDir) {
    const results = [];
    const files = fs.readdirSync(workflowsDir)
        .filter(f => f.endsWith('.yml') || f.endsWith('.yaml'));

    for (const file of files) {
        const filePath = path.join(workflowsDir, file);
        const content = fs.readFileSync(filePath, 'utf8');

        let parsed;
        try {
            parsed = yaml.parse(content);
        } catch (e) {
            core.warning(`Failed to parse ${file}: ${e.message}`);
            continue;
        }

        if (!parsed || !parsed.jobs) continue;

        for (const [jobName, job] of Object.entries(parsed.jobs)) {
            const jobWith = job.with || {};
            const sourceImageOs = jobWith['source-image-os'];

            if (sourceImageOs && typeof sourceImageOs === 'string' && sourceImageOs.trim() !== '') {
                results.push({
                    file,
                    filePath,
                    jobName,
                    currentOs: sourceImageOs.trim(),
                    sourceImageNamespace: jobWith['source-image-namespace'] || 'library',
                    sourceImageName: jobWith['source-image-name'] || '',
                    sourceImageType: jobWith['source-image-type'] || '',
                    targetImageName: jobWith['image-name'] || '',
                    targetImageType: jobWith['image-type'] || '',
                    trackedVersions: parseInt(jobWith['tracked-versions'] || '1', 10),
                    versionPrecision: parseInt(jobWith['version-precision'] || '3', 10),
                });
            }
        }
    }

    return results;
}

module.exports = {findDebianAwareJobs};
