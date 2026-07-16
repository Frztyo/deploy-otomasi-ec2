const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || '1.0.0';

app.get('/', (req, res) => {
  res.send(`Aplikasi berjalan - Versi ${VERSION}`);
});

// Endpoint health check sesuai rancangan BAB III
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK', version: VERSION });
});

app.listen(PORT, () => {
  console.log(`Server berjalan di port ${PORT}`);
});

