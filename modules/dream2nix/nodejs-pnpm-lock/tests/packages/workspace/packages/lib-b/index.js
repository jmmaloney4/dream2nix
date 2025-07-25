const libA = require('@workspace/lib-a');

module.exports = {
  name: '@workspace/lib-b',
  version: require('./package.json').version,
  useLibA: () => libA.shuffle([1, 2, 3])
};