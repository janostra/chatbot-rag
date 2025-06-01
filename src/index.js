require('dotenv').config();
const express = require('express');
const app = express();
const messageRoutes = require('./routes/messageRoutes');
const path = require('path');
// require('./db/db');


app.use(express.static(path.join(__dirname, '../public')));
app.use(express.json());
app.use('/api/messages', messageRoutes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Servidor corriendo en http://localhost:${PORT}`);
});
