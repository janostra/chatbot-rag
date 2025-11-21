import express from "express";
import mongoose from "mongoose";
import fetch from "node-fetch";
import sdk from "microsoft-cognitiveservices-speech-sdk";
import dotenv from "dotenv";
import cors from "cors";
import path from "path";
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Cargar .env desde la raíz
dotenv.config({ path: path.join(__dirname, "..", ".env") });

const app = express();
app.use(express.json());
app.use(cors());

// Servir solo la carpeta /public
app.use(express.static(path.join(__dirname, "public")));

const PORT = process.env.PORT || 3000;

// Ruta principal -> index.html
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

// Conexión a Cosmos DB (Mongo API)
mongoose.connect(process.env.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
}).then(() => {
  console.log("✅ Conectado a Cosmos DB");
}).catch(err => {
  console.error("❌ Error conectando a Cosmos DB:", err);
});

// Modelo simple de conversación
const Conversation = mongoose.model("Conversation", {
  conversationId: String,
  question: String,
  answer: String,
  createdAt: { type: Date, default: Date.now },
});

// Health check
app.get("/health", (req, res) => {
  res.json({ 
    status: "ok", 
    database: mongoose.connection.readyState === 1 ? "connected" : "disconnected"
  });
});

// Endpoint que conecta al backend RAG
app.post("/ask", async (req, res) => {
  const { query, conversationId = `conv_${Date.now()}` } = req.body;
  
  if (!query || query.trim() === "") {
    return res.status(400).json({ error: "La pregunta no puede estar vacía" });
  }

  try {
    // Llamar al backend Python (RAG)
    const response = await fetch(`${process.env.RAG_ENDPOINT}/ask`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: query }),
    });

    if (!response.ok) {
      throw new Error(`Error del backend RAG: ${response.status}`);
    }

    const data = await response.json();
    const answer = data.answer || "Lo siento, no pude generar una respuesta.";

    // Guardar en Cosmos DB
    await Conversation.create({ 
      conversationId,
      question: query, 
      answer: answer 
    });

    res.json({ 
      answer,
      conversationId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error("Error en /ask:", err);
    res.status(500).json({ 
      error: "Error procesando tu pregunta",
      details: err.message 
    });
  }
});

// Endpoint de texto a voz (TTS)
app.post("/tts", async (req, res) => {
  const { text } = req.body;
  
  if (!text || text.trim() === "") {
    return res.status(400).json({ error: "El texto no puede estar vacío" });
  }

  try {
    const speechConfig = sdk.SpeechConfig.fromSubscription(
      process.env.SPEECH_KEY,
      process.env.SPEECH_REGION
    );
    
    // Voz en español argentino
    speechConfig.speechSynthesisVoiceName = "es-AR-ElenaNeural";
    speechConfig.speechSynthesisOutputFormat = sdk.SpeechSynthesisOutputFormat.Audio16Khz32KBitRateMonoMp3;

    const synthesizer = new sdk.SpeechSynthesizer(speechConfig);

    synthesizer.speakTextAsync(
      text,
      result => {
        if (result.reason === sdk.ResultReason.SynthesizingAudioCompleted) {
          const audioData = result.audioData;
          const base64Audio = Buffer.from(audioData).toString("base64");
          
          synthesizer.close();
          res.json({ 
            success: true,
            audio: base64Audio,
            format: "mp3"
          });
        } else {
          synthesizer.close();
          res.status(500).json({ error: "Error en síntesis de voz" });
        }
      },
      err => {
        console.error("Error TTS:", err);
        synthesizer.close();
        res.status(500).json({ error: "Error al convertir voz" });
      }
    );
  } catch (error) {
    console.error("Error general TTS:", error);
    res.status(500).json({ error: "Error en el servicio de voz" });
  }
});

app.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════╗
║  🚀 Servidor corriendo en puerto ${PORT}  ║
║  📍 http://localhost:${PORT}            ║
╚════════════════════════════════════════╝
  `);
});