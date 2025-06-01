const { textToSpeech, speechToText } = require('../services/elevenLabsService');
const { consultarEmpresa } = require('../services/ragService'); // solo RAG

async function handleMessage(req, res) {
  try {
    let { message, audioBase64, wantAudio } = req.body;

    // Si llega audio, convertir a texto
    if (audioBase64) {
      const audioBuffer = Buffer.from(audioBase64, 'base64');
      message = await speechToText(audioBuffer);
    }

    if (!message) return res.status(400).json({ error: 'Mensaje requerido' });

    const replyText = await consultarEmpresa(message);

    // Si quiere voz, convertir respuesta a audio base64
    if (wantAudio) {
      const audioBuffer = await textToSpeech(replyText);
      const audioBase64Response = audioBuffer.toString('base64');
      return res.json({ reply: replyText, audioBase64: audioBase64Response });
    }

    res.json({ reply: replyText });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
}

module.exports = { handleMessage };
