const path = require('node:path');
const fs = require('node:fs');
const yaml = require('yaml');
const constants = require('./util/constants');
const {getAllTags, parseVersionTags} = require('./util/docker-version-utils');
const {generateBuildMatrix} = require('./util/build-matrix-generation');
const child_process = require('node:child_process');

/* =============================
 * IMPORTANT!
 *
 * This is a development helper script, to locally build a specific image version
 * See the /bin/build.sh script for how to use it. It will internally call this script.
 * ============================= */

(async () => {
    const imageName = process.argv[2] || '';
    const sourceVersion = process.argv[3] || '';
    const imageTypeInput = process.argv[4] || '';

    if (!imageName || !sourceVersion) {
        console.error('Image name and source version are required arguments.');
        // Show usage
        console.error('Usage: bin/build.sh <image-name> <source-version> [image-type]');
        process.exit(1);
    }

    const workflowFilePath = path.join(__dirname, '..', 'workflows', imageName + '.yml');

    if (!fs.existsSync(workflowFilePath)) {
        console.error(`Workflow file for image "${imageName}" does not exist at path: ${workflowFilePath}`);
        process.exit(1);
    }

    const workflowContent = fs.readFileSync(workflowFilePath, 'utf-8');
    const workflowData = yaml.parse(workflowContent);
    const workflowJobs = workflowData.jobs || {};

    const targetJobCandidates = ['call-build-engine'];
    if (imageTypeInput) {
        targetJobCandidates.push(`call-build-engine-${imageTypeInput}`);
        targetJobCandidates.push(`call-${imageTypeInput}`);
    }

    let targetJob = null;
    for (const candidate of targetJobCandidates) {
        if (workflowJobs[candidate]) {
            targetJob = workflowJobs[candidate];
            break;
        }
    }

    if (!targetJob) {
        console.error(`No suitable job found in the workflow file for image "${imageName}". Checked candidates: "${targetJobCandidates.join('", "')}" against available jobs: "${Object.keys(workflowJobs).join('", "')}"`);
        process.exit(1);
    }

    const jobWith = targetJob ? targetJob.with || {} : {};
    if (jobWith['image-name'] && jobWith['image-name'] !== imageName) {
        console.error(`The "image-name" in the job definition does not match the provided image name.`);
        process.exit(1);
    }

    const imageType = jobWith['image-type'] || '';
    const sourceImageNamespace = jobWith['source-image-namespace'] || '';
    const sourceImageName = jobWith['source-image-name'] || '';

    if (!sourceImageNamespace || !sourceImageName) {
        console.error('Source image namespace and name must be defined in the workflow file.');
        process.exit(1);
    }

    const sourceImageType = jobWith['source-image-type'] || '';
    const trackedVersions = parseInt(jobWith['tracked-versions'] || '3', 10);
    const deprecatedVersion = jobWith['deprecated'] || '';
    const versionPrecision = parseInt(jobWith['version-precision'] || '3', 10);
    const detectLatestVersion = typeof jobWith['latest-tag'] === 'boolean'
        ? jobWith['latest-tag']
        : (jobWith['latest-tag'] || 'false').toLowerCase() === 'true';

    const sourceImage = `${sourceImageNamespace}/${sourceImageName}`;
    const targetImage = `${constants.IMAGE_NAMESPACE}/${imageName}`;

    console.log('Building image:', targetImage);
    console.log('Using source image:', sourceImage);
    console.log('Source version to build:', sourceVersion);
    console.log('Image type:', imageType);
    console.log('Tracked versions:', trackedVersions);
    console.log('Deprecated version:', deprecatedVersion);
    console.log('Version precision:', versionPrecision);
    console.log('Detect latest version:', detectLatestVersion);

    const allSourceTags = await getAllTags(sourceImage);
    const sourceVersions = parseVersionTags(allSourceTags, versionPrecision, sourceImageType);

    if (!sourceVersions.has(sourceVersion)) {
        console.error(`Source version "${sourceVersion}" not found among available source image tags.`);
        console.log('Available source versions:', Array.from(sourceVersions.keys()));
        process.exit(1);
    }

    const buildMatrix = generateBuildMatrix({
        sourceImage,
        sourceVersions: new Map([[sourceVersion, sourceVersions.get(sourceVersion)]]),
        targetImageName: imageName,
        targetImageType: imageType,
        detectLatestVersion: false,
        trackedVersions: 1
    });

    if (buildMatrix === null) {
        console.error('No build matrix could be generated for the specified source version.');
        process.exit(1);
    }

    const buildEntry = buildMatrix.include[0];
    console.log('Build Entry:');
    console.log(` - Version: ${buildEntry.version}`);
    console.log(` - Tag: ${buildEntry.tag}`);
    console.log(` - Source Image with Tag: ${buildEntry.sourceImageWithTag}`);
    console.log(` - Build Path: ${buildEntry.buildPath}`);

    let commonDirPath = path.join(__dirname, '..', '..', 'src', '_common');

    const dockerBuildCommand = `cd "${buildEntry.buildPath}" && docker build -t ${targetImage}:${buildEntry.tag} --build-context common="${commonDirPath}" --progress=plain --build-arg SOURCE_IMAGE=${buildEntry.sourceImageWithTag} .`;
    child_process.execSync(dockerBuildCommand, {stdio: 'inherit'});
})();
