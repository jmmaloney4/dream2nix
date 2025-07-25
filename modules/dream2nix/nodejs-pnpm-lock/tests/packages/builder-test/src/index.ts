import express from 'express';
import * as _ from 'lodash';

const app = express();
const port = 3000;

app.get('/', (req, res) => {
  const data = _.shuffle([1, 2, 3, 4, 5]);
  res.json({
    message: 'Hello from pnpm + TypeScript!',
    shuffled: data,
    timestamp: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});