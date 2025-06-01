// src/services/ragService.js
const axios = require('axios');

async function consultarEmpresa(pregunta) {
  try {
    const response = await axios.post('http://localhost:8000/query', {
      question: pregunta,
    });
    return response.data.answer;
  } catch (error) {
    console.error('Error al consultar RAG:', error.message);
    return null;
  }
}

module.exports = { consultarEmpresa };
