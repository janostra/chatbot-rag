const axios = require('axios');
const FormData = require('form-data');

const ELEVEN_API_KEY = process.env.ELEVEN_API_KEY;
const ELEVEN_VOICE_ID = process.env.ELEVEN_VOICE_ID;

// Convierte texto a audio (mp3) y devuelve buffer
async function textToSpeech(text) {
  try {
    const response = await axios.post(
      `https://api.elevenlabs.io/v1/text-to-speech/${ELEVEN_VOICE_ID}`,
      { text },
      {
        headers: {
          'xi-api-key': ELEVEN_API_KEY,
          'Content-Type': 'application/json',
        },
        responseType: 'arraybuffer',
      }
    );
    return Buffer.from(response.data);
  } catch (error) {
    console.error('Error en TTS:', error.response?.data || error.message);
    throw error;
  }
}

// Convierte audio (mp3 buffer) a texto
async function speechToText(audioBuffer) {
  try {
    const formData = new FormData();
    formData.append('file', audioBuffer, {
      filename: 'audio.mp3',
      contentType: 'audio/mpeg',
    });

    const response = await axios.post(
      'https://api.elevenlabs.io/v1/speech-to-text',
      formData,
      {
        headers: {
          ...formData.getHeaders(),
          'xi-api-key': ELEVEN_API_KEY,
        },
      }
    );

    return response.data.text;
  } catch (error) {
    console.error('Error en STT:', error.response?.data || error.message);
    throw error;
  }
}

module.exports = { textToSpeech, speechToText };
