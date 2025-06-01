const mongoose = require('mongoose');

const clientSchema = new mongoose.Schema({
  dni: { type: String, unique: true, required: true },
  nombre: String,
  apellido: String,
  fechaNacimiento: Date,
  tel: Number,
  email: String,
  serviciosContratados: [String],
  ultimaInteraccion: Date,
});

const Client = mongoose.model('Client', clientSchema);

module.exports = Client;
