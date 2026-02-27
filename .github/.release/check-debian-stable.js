const path = require('path');
const core = require('@actions/core');
const {fetchStableCodename} = require('./modules/check-debian-stable/fetch-stable-codename');
const {findDebianAwareJobs} = require('./modules/check-debian-stable/find-debian-aware-jobs');
const {verifyJobs, updateWorkflowFiles} = require('./modules/check-debian-stable/verify-and-update');
const {createOrUpdatePullRequest} = require('./modules/check-debian-stable/create-or-update-pull-request');

const WORKFLOWS_DIR = path.join(__dirname, '..', 'workflows');

(async () => {
    try {
        core.info('Fetching current Debian stable codename...');
        const stableCodename = await fetchStableCodename();
        core.info(`Current Debian stable: ${stableCodename}`);

        core.info('Scanning workflow files for debian-aware jobs...');
        const jobs = findDebianAwareJobs(WORKFLOWS_DIR);

        if (jobs.length === 0) {
            core.info('No debian-aware jobs found. Nothing to do.');
            return;
        }

        core.info(`Found ${jobs.length} debian-aware job(s):`);
        for (const job of jobs) {
            core.info(`  ${job.file} / ${job.jobName}: current='${job.currentOs}', source=${job.sourceImageNamespace}/${job.sourceImageName}`);
        }

        const jobsNeedingUpdate = jobs.filter(j => j.currentOs !== stableCodename);

        if (jobsNeedingUpdate.length === 0) {
            core.info(`All jobs already use '${stableCodename}'. Nothing to do.`);
            return;
        }

        const currentCodename = jobsNeedingUpdate[0].currentOs;
        core.info(`Update needed: '${currentCodename}' → '${stableCodename}'`);

        core.info('Verifying upstream image availability...');
        const {verificationResults, allVerified} = await verifyJobs(jobs, stableCodename);

        core.info('Updating workflow files...');
        const updatedFiles = updateWorkflowFiles(jobsNeedingUpdate, stableCodename);
        core.info(`Updated ${updatedFiles.length} file(s): ${updatedFiles.join(', ')}`);

        if (!process.env.GITHUB_ACTIONS) {
            core.info('Not running in GitHub Actions, skipping PR operations');
            core.info(`All verified: ${allVerified}`);
            return;
        }

        createOrUpdatePullRequest({
            branchName: `debian-stable/${stableCodename}`,
            commitMessage: `chore(deps): update Debian stable from ${currentCodename} to ${stableCodename}`,
            title: `chore(deps): update Debian stable from ${currentCodename} to ${stableCodename}`,
            currentCodename,
            newCodename: stableCodename,
            allVerified,
            updatedFiles,
            verificationResults,
            isDraft: !allVerified,
            updatedFilePaths: updatedFiles.map(f => path.join(WORKFLOWS_DIR, f)),
        });

    } catch (error) {
        core.setFailed(`Debian stable check failed: ${error.message}`);
    }
})();
