const path = require('node:path');
/**
 * The directory where the source code for different image versions is located
 * @type {string}
 */
const SOURCE_BASE_DIR = path.join(__dirname, '..', '..', '..', 'src');

/**
 * The namespace used for Docker images
 * @type {string}
 */
const IMAGE_NAMESPACE = 'neunerlei';

/**
 * The directory where templates to use in the build process are located
 * @type {string}
 */
const BUILD_TEMPLATE_DIR = path.join(__dirname, '..', 'templates');

/**
 * The directory where build outputs are stored
 * @type {string}
 */
const BUILD_OUTPUT_DIR = path.join(__dirname, '..', 'build');

module.exports = {
    SOURCE_BASE_DIR,
    IMAGE_NAMESPACE,
    BUILD_TEMPLATE_DIR,
    BUILD_OUTPUT_DIR
};
