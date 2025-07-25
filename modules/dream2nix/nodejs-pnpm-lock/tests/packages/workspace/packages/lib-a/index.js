const _ = require('lodash');

module.exports = {
  name: '@workspace/lib-a',
  shuffle: _.shuffle,
  version: require('./package.json').version
};