const libA = require('@workspace/lib-a');
const libB = require('@workspace/lib-b');

console.log('Web App using:');
console.log('- lib-a:', libA.name, 'v' + libA.version);
console.log('- lib-b:', libB.name, 'v' + libB.version);
console.log('- lib-b using lib-a:', libB.useLibA());