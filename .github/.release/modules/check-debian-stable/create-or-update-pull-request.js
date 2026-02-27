const fs = require('fs');
const path = require('path');
const core = require('@actions/core');
const {run, runSafe} = require('../../util/shell');
const constants = require('../../util/constants');

/**
 * Generates the PR body markdown.
 * @param {string} currentCodename
 * @param {string} newCodename
 * @param {boolean} allVerified
 * @param {string[]} updatedFiles
 * @param {Object<string, import('./verify-and-update').VerificationResult>} verificationResults
 * @returns {string}
 */
function buildPrBody(currentCodename, newCodename, allVerified, updatedFiles, verificationResults) {
    const lines = [
        `## Debian Stable Update: ${currentCodename} → ${newCodename}`,
        '',
    ];

    if (allVerified) {
        lines.push('✅ **All upstream images verified.** This PR is ready to merge.');
    } else {
        lines.push(
            '⏳ **Waiting for upstream images.** This PR will be marked as ready for review automatically once all checks pass.'
        );
    }

    lines.push('', '### Verification Results', '');

    for (const [, result] of Object.entries(verificationResults)) {
        const icon = result.passed ? '✅' : '❌';
        let line = `- ${icon} \`${result.sourceImage}\` (filter: \`${result.imageFilter}\`)`;

        if (result.buildableVersions.length > 0) {
            line += ` — buildable: ${result.buildableVersions.join(', ')}`;
        } else {
            line += ` — no buildable versions`;
        }

        if (result.noBuildPath.length > 0) {
            line += ` · skipped (no build path): ${result.noBuildPath.join(', ')}`;
        }

        if (result.missingCodename.length > 0) {
            line += ` · ⚠️ awaiting tag: ${result.missingCodename.join(', ')}`;
        }

        lines.push(line);
    }

    lines.push('', '### Updated Files', '');
    for (const file of updatedFiles) {
        lines.push(`- \`${file}\``);
    }

    lines.push(
        '',
        '---',
        `*This PR was automatically created by the Debian stable version checker. Last checked: ${new Date().toISOString()}*`,
    );

    return lines.join('\n');
}

/**
 * Writes the PR body to a file.
 * @param {string} body
 * @returns {string} Absolute path to the written file
 */
function writePrBodyFile(body) {
    const outputDir = constants.BUILD_OUTPUT_DIR;
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, {recursive: true});
    }
    const filePath = path.join(outputDir, 'debian-update-pr-body.md');
    fs.writeFileSync(filePath, body);
    return filePath;
}

/**
 * Creates or updates a pull request for the Debian stable transition.
 * Handles branching, committing, pushing, body generation, and draft status.
 *
 * @param {Object} options
 * @param {string} options.branchName
 * @param {string} options.commitMessage
 * @param {string} options.title
 * @param {string} options.currentCodename
 * @param {string} options.newCodename
 * @param {boolean} options.allVerified
 * @param {string[]} options.updatedFiles - Filenames for the PR body
 * @param {Object<string, import('./verify-and-update').VerificationResult>} options.verificationResults
 * @param {boolean} options.isDraft
 * @param {string[]} options.updatedFilePaths - Absolute paths for git add
 */
function createOrUpdatePullRequest({
                                       branchName, commitMessage, title,
                                       currentCodename, newCodename, allVerified,
                                       updatedFiles, verificationResults,
                                       isDraft, updatedFilePaths
                                   }) {
    // Generate PR body
    const prBody = buildPrBody(currentCodename, newCodename, allVerified, updatedFiles, verificationResults);
    const prBodyFile = writePrBodyFile(prBody);

    // Configure git identity
    run('git config user.name "github-actions[bot]"');
    run('git config user.email "github-actions[bot]@users.noreply.github.com"');

    // Create branch from current HEAD and stage workflow files
    run(`git checkout -B "${branchName}"`);
    for (const filePath of updatedFilePaths) {
        run(`git add "${filePath}"`);
    }

    // Commit and push
    const staged = run('git diff --cached --name-only');
    if (staged) {
        run(`git commit -m "${commitMessage}"`);
        run(`git push origin "${branchName}" --force`);
    } else {
        core.info('No file changes to commit, updating PR metadata only');
    }

    // Find existing PR for this branch
    const existingPrNumber = runSafe(
        `gh pr list --head "${branchName}" --json number --jq ".[0].number"`
    );

    let prNumber;

    if (existingPrNumber) {
        prNumber = existingPrNumber;
        core.info(`Found existing PR #${prNumber}, updating body`);
        run(`gh pr edit "${prNumber}" --body-file "${prBodyFile}"`);
    } else {
        core.info('Creating new draft pull request...');
        const prUrl = run(
            `gh pr create --head "${branchName}" --title "${title}" --body-file "${prBodyFile}" --draft`
        );
        core.info(`Created PR: ${prUrl}`);
        prNumber = runSafe(
            `gh pr list --head "${branchName}" --json number --jq ".[0].number"`
        );
    }

    if (!prNumber) {
        core.warning('Could not determine PR number, skipping draft status update');
        return;
    }

    // Synchronize draft status
    if (isDraft) {
        runSafe(`gh pr ready "${prNumber}" --undo`);
    } else {
        core.info(`Marking PR #${prNumber} as ready for review`);
        runSafe(`gh pr ready "${prNumber}"`);
    }
}

module.exports = {createOrUpdatePullRequest};
