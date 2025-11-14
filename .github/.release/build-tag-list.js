const constants = require('./util/constants');
const path = require('node:path');
const core = require('@actions/core');
const semver = require('semver');
const fs = require('fs');
const {sortVersionList} = require('./util/docker-version-utils');

/**
 * Expects the OUTPUT<image> of discover-build-matrix.js, which contains the full docker image name without the tag
 * @type {string}
 */
const imageInput = core.getInput('image', {required: true});
/**
 * Expects the OUTPUT<image-name> of discover-build-matrix.js, which contains the image name and optional type
 * @type {string}
 */
const imageNameInput = core.getInput('image-name', {required: true});
/**
 * Expects the OUTPUT<deprecated> of discover-build-matrix.js, which indicates if the image is deprecated
 * @type {boolean}
 */
const deprecatedInput = core.getBooleanInput('deprecated');
/**
 * Expects the OUTPUT<tag-list-maintained> of discover-build-matrix.js, which contains a comma-separated list of maintained tags
 * @type {string[]}
 */
const maintainedTagsInput = core.getInput('maintained-tags', {required: true}).split(',').filter(t => t);
/**
 * Expects the OUTPUT<tag-list-all> of discover-build-matrix.js, which contains a comma-separated list of all discovered tags
 * @type {string[]}
 */
const allTagsInput = core.getInput('all-tags', {required: true}).split(',').filter(t => t);
/**
 * Expects the OUTPUT<tag-list-latest-built> of discover-build-matrix.js, which indicates if the latest tag is built
 * @type {boolean}
 */
const latestTagBuiltInput = core.getBooleanInput('latest-tag-built', {required: true});

core.info('Generating tag list HTML file');

if(!imageInput || imageInput.length === 0){
    throw new Error('Input "image" is required');
}
if(!imageNameInput || imageNameInput.length === 0){
    throw new Error('Input "image-name" is required');
}
const image = imageInput;
const imageName = imageNameInput;
const deprecated = deprecatedInput;

// Sort tag lists, so the newest version comes first
const maintainedTags = sortVersionList(maintainedTagsInput);
const availableTags = sortVersionList(allTagsInput).filter(tag => !maintainedTags.includes(tag));

if(latestTagBuiltInput){
    maintainedTags.unshift('latest');
}

core.info(`Maintained Tags (${maintainedTags.length}): ${maintainedTags.join(', ')}`);
core.info(`Available Tags (${availableTags.length}): ${availableTags.join(', ')}`);

/**
 * Escapes special characters in a string for use in a regular expression.
 * @param string
 * @return {string}
 */
function escapeRegex(string) {
    return string.replace(/[/\-\\^$*+?.()|[\]{}]/g, '\\$&');
}

/**
 * Renders a template file with the provided data.
 * The template placeholders are in the format ${KEY}, where KEY is the uppercase version of the data keys.
 * If a key is not found in the data (e.g. being undefined), it will be replaced with an empty string.
 * @param {string} template The template file name, relative to the BUILD_TEMPLATE_DIR
 * @param {Object} data Key-value pairs to replace in the template
 * @return {string}
 */
function renderTemplate(template, data) {
    const templatePath = path.join(constants.BUILD_TEMPLATE_DIR, template);
    let content = require('fs').readFileSync(templatePath, 'utf8');


    for (const key in data) {
        const placeholder = `\${${key.toUpperCase()}}`;
        content = content.replace(new RegExp(escapeRegex(placeholder), 'g'), data[key] ?? '');
    }

    return content;
}

function renderTagList(tagList) {
    return tagList.map(tag => renderTemplate('taglist/tag.html.tpl', {TAG: tag, IMAGE: image})).join('\n');
}

function renderSection(tagList, template) {
    if (tagList.length === 0) {
        return;
    }

    const tags = renderTagList(tagList);
    return renderTemplate(template, {TAGS: tags});
}

function renderDeprecatedWarning() {
    if (!deprecated) {
        return;
    }

    const hasMaintainedTags = maintainedTags.length > 0;
    const message = hasMaintainedTags ?
        `, for a limited time the following versions will still be built regularly: <strong>${maintainedTags.join(', ')}</strong>`
        : '.';

    return renderTemplate('taglist/warning.deprecated.html.tpl', {message});
}

const index = renderTemplate('taglist/index.html.tpl', {
    IMAGE: image,
    IMAGE_NAME: imageName,
    DEPRECATED_WARNING: renderDeprecatedWarning(),
    DEPRECATED_SECTION: deprecated ? renderSection(maintainedTags.concat(availableTags), 'taglist/section.deprecated.html.tpl') : '',
    MAINTAINED_SECTION: deprecated ? '' : renderSection(maintainedTags, 'taglist/section.maintained.html.tpl'),
    AVAILABLE_SECTION: deprecated ? '' : renderSection(availableTags, 'taglist/section.available.html.tpl')
});

function imageNameToFilename(imageName) {
    // Everything that is not a-z, A-Z, 0-9, -, _ is replaced with -
    // Replace duplicated - with a single -
    // Remove leading and trailing -
    return imageName
        .replace(/[^a-zA-Z0-9-_]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-/, '')
        .replace(/-$/, '');
}

const fileName = `${imageNameToFilename(imageName)}-tags.html`;
const outputDir = path.join(constants.BUILD_OUTPUT_DIR, 'tag-lists');
if(!fs.existsSync(outputDir)){
    fs.mkdirSync(outputDir, {recursive: true});
}
const outputPath = path.join(outputDir, fileName);
core.info(`Writing tag list HTML file to: ${outputPath}`);

fs.writeFileSync(outputPath, index);

/**
 * The path to the generated tag list HTML file
 */
core.setOutput('tag-list-file', outputPath);
/**
 * The output directory containing the tag list HTML file
 * This can be used to upload the directory as an artifact, e.g. for later publishing
 */
core.setOutput('tag-list-output-dir', outputDir);
