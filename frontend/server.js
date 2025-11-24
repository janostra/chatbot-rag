import express from "express";
import mongoose from "mongoose";
import fetch from "node-fetch";
import sdk from "microsoft-cognitiveservices-speech-sdk";
import dotenv from "dotenv";
import cors from "cors";
import path from "path";
import { fileURLToPath } from 'url';
import { BlobServiceClient } from '@azure/storage-blob';
import appInsights from 'applicationinsights';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// ============================================
// CONFIGURAR APPLICATION INSIGHTS
// ============================================
if (process.env.APPINSIGHTS_CONNECTION_STRING) {
  appInsights.setup(process.env.APPINSIGHTS_CONNECTION_STRING)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true)
    .start();
  
  console.log("✅ Application Insights configurado");
}

const client = appInsights.defaultClient;

const app = express();
app.use(express.json({ limit: '50mb' }));
app.use(cors());
app.use(express.static(path.join(__dirname, "public")));

const PORT = process.env.PORT || 3000;

// ============================================
// CONFIGURAR BLOB STORAGE
// ============================================
let blobServiceClient;
if (process.env.AZURE_STORAGE_CONNECTION_STRING) {
  blobServiceClient = BlobServiceClient.fromConnectionString(
    process.env.AZURE_STORAGE_CONNECTION_STRING
  );
  console.log("✅ Blob Storage configurado");
}

// ============================================
// MULTER PARA ARCHIVOS
// ============================================
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB
});

// ============================================
// CONEXIÓN A COSMOS DB
// ============================================
mongoose.connect(process.env.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
}).then(() => {
  console.log("✅ Conectado a Cosmos DB");
  if (client) {
    client.trackEvent({ name: "DatabaseConnected" });
  }
}).catch(err => {
  console.error("❌ Error conectando a Cosmos DB:", err);
  if (client) {
    client.trackException({ exception: err });
  }
});

// ============================================
// MODELOS
// ============================================
const Conversation = mongoose.model("Conversation", {
  conversationId: String,
  userId: { type: String, default: "anonymous" },
  question: String,
  answer: String,
  responseTime: Number,
  createdAt: { type: Date, default: Date.now },
});

const Document = mongoose.model("Document", {
  documentId: String,
  filename: String,
  blobUrl: String,
  uploadedAt: { type: Date, default: Date.now },
  indexed: { type: Boolean, default: false },
});

// ============================================
// ROUTES
// ============================================

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.get("/health", (req, res) => {
  const health = {
    status: "ok",
    timestamp: new Date().toISOString(),
    services: {
      database: mongoose.connection.readyState === 1 ? "connected" : "disconnected",
      blobStorage: blobServiceClient ? "configured" : "not configured",
      appInsights: client ? "active" : "not configured",
      rag: process.env.RAG_ENDPOINT ? "configured" : "not configured"
    }
  };
  
  res.json(health);
});

// ============================================
// ENDPOINT: CHAT CON RAG
// ============================================
app.post("/ask", async (req, res) => {
  const startTime = Date.now();
  const { query, conversationId = `conv_${Date.now()}`, userId = "anonymous" } = req.body;
  
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
    const responseTime = Date.now() - startTime;

    // Guardar en Cosmos DB
    await Conversation.create({ 
      conversationId,
      userId,
      question: query, 
      answer: answer,
      responseTime
    });

    // Trackear en Application Insights
    if (client) {
      client.trackEvent({
        name: "ChatQuery",
        properties: {
          conversationId,
          userId,
          queryLength: query.length,
          responseTime,
          hasAnswer: !!answer
        },
        measurements: {
          responseTime
        }
      });

      client.trackMetric({
        name: "ResponseTime",
        value: responseTime
      });
    }

    res.json({ 
      answer,
      conversationId,
      responseTime,
      timestamp: new Date().toISOString()
    });

  } catch (err) {
    console.error("Error en /ask:", err);
    
    if (client) {
      client.trackException({
        exception: err,
        properties: {
          endpoint: "/ask",
          query: query.substring(0, 50)
        }
      });
    }
    
    res.status(500).json({ 
      error: "Error procesando tu pregunta",
      details: process.env.NODE_ENV === "development" ? err.message : undefined
    });
  }
});

// ============================================
// ENDPOINT: SPEECH-TO-TEXT (STT)
// ============================================
app.post("/stt", async (req, res) => {
  const startTime = Date.now();
  
  try {
    const { audioData } = req.body; // Base64 audio
    
    if (!audioData) {
      return res.status(400).json({ error: "No se recibió audio" });
    }

    const speechConfig = sdk.SpeechConfig.fromSubscription(
      process.env.SPEECH_KEY,
      process.env.SPEECH_REGION
    );
    
    speechConfig.speechRecognitionLanguage = "es-AR";

    // Convertir base64 a buffer
    const audioBuffer = Buffer.from(audioData, 'base64');
    
    // Crear formato de audio
    const pushStream = sdk.AudioInputStream.createPushStream();
    pushStream.write(audioBuffer);
    pushStream.close();
    
    const audioConfig = sdk.AudioConfig.fromStreamInput(pushStream);
    const recognizer = new sdk.SpeechRecognizer(speechConfig, audioConfig);

    recognizer.recognizeOnceAsync(
      result => {
        const responseTime = Date.now() - startTime;
        
        if (result.reason === sdk.ResultReason.RecognizedSpeech) {
          if (client) {
            client.trackEvent({
              name: "SpeechToText",
              properties: {
                textLength: result.text.length,
                success: true
              },
              measurements: {
                responseTime
              }
            });
          }
          
          res.json({ 
            text: result.text, 
            success: true,
            responseTime
          });
        } else {
          res.status(400).json({ 
            error: "No se reconoció voz clara",
            success: false 
          });
        }
        
        recognizer.close();
      },
      error => {
        console.error("Error STT:", error);
        
        if (client) {
          client.trackException({ exception: error });
        }
        
        res.status(500).json({ error: "Error en reconocimiento de voz" });
        recognizer.close();
      }
    );

  } catch (error) {
    console.error("Error general STT:", error);
    
    if (client) {
      client.trackException({ exception: error });
    }
    
    res.status(500).json({ error: "Error en el servicio de voz" });
  }
});

// ============================================
// ENDPOINT: TEXT-TO-SPEECH (TTS)
// ============================================
app.post("/tts", async (req, res) => {
  const startTime = Date.now();
  const { text } = req.body;
  
  if (!text || text.trim() === "") {
    return res.status(400).json({ error: "El texto no puede estar vacío" });
  }

  try {
    const speechConfig = sdk.SpeechConfig.fromSubscription(
      process.env.SPEECH_KEY,
      process.env.SPEECH_REGION
    );
    
    speechConfig.speechSynthesisVoiceName = "es-AR-ElenaNeural";
    speechConfig.speechSynthesisOutputFormat = 
      sdk.SpeechSynthesisOutputFormat.Audio16Khz32KBitRateMonoMp3;

    const synthesizer = new sdk.SpeechSynthesizer(speechConfig);

    synthesizer.speakTextAsync(
      text,
      result => {
        const responseTime = Date.now() - startTime;
        
        if (result.reason === sdk.ResultReason.SynthesizingAudioCompleted) {
          const audioData = result.audioData;
          const base64Audio = Buffer.from(audioData).toString("base64");
          
          if (client) {
            client.trackEvent({
              name: "TextToSpeech",
              properties: {
                textLength: text.length,
                success: true
              },
              measurements: {
                responseTime,
                audioSize: audioData.byteLength
              }
            });
          }
          
          synthesizer.close();
          res.json({ 
            success: true,
            audio: base64Audio,
            format: "mp3",
            responseTime
          });
        } else {
          synthesizer.close();
          res.status(500).json({ error: "Error en síntesis de voz" });
        }
      },
      err => {
        console.error("Error TTS:", err);
        
        if (client) {
          client.trackException({ exception: err });
        }
        
        synthesizer.close();
        res.status(500).json({ error: "Error al convertir voz" });
      }
    );
  } catch (error) {
    console.error("Error general TTS:", error);
    
    if (client) {
      client.trackException({ exception: error });
    }
    
    res.status(500).json({ error: "Error en el servicio de voz" });
  }
});

// ============================================
// ENDPOINT: SUBIR DOCUMENTO A BLOB STORAGE
// ============================================
app.post("/upload-document", upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: "No se recibió archivo" });
    }

    if (!blobServiceClient) {
      return res.status(503).json({ error: "Blob Storage no configurado" });
    }

    const documentId = uuidv4();
    const filename = `${documentId}-${req.file.originalname}`;
    
    // Subir a Blob Storage
    const containerClient = blobServiceClient.getContainerClient("documents");
    
    // Crear container si no existe
    await containerClient.createIfNotExists({
      access: 'blob'
    });
    
    const blockBlobClient = containerClient.getBlockBlobClient(filename);
    
    await blockBlobClient.upload(
      req.file.buffer, 
      req.file.buffer.length
    );

    const blobUrl = blockBlobClient.url;

    // Guardar metadata en Cosmos DB
    const doc = await Document.create({
      documentId,
      filename: req.file.originalname,
      blobUrl,
      indexed: false
    });

    if (client) {
      client.trackEvent({
        name: "DocumentUploaded",
        properties: {
          filename: req.file.originalname,
          size: req.file.size,
          documentId
        }
      });
    }

    // TODO: Triggear Azure Function para re-indexar
    // O llamar directamente a Python script

    res.json({ 
      success: true, 
      documentId,
      filename: req.file.originalname,
      blobUrl,
      message: "Documento subido. Se indexará próximamente."
    });

  } catch (error) {
    console.error("Error subiendo documento:", error);
    
    if (client) {
      client.trackException({ exception: error });
    }
    
    res.status(500).json({ error: "Error subiendo documento" });
  }
});

// ============================================
// ENDPOINT: LISTAR DOCUMENTOS
// ============================================
app.get("/documents", async (req, res) => {
  try {
    const documents = await Document.find()
      .sort({ uploadedAt: -1 })
      .limit(50);
    
    res.json({ documents });
  } catch (error) {
    console.error("Error listando documentos:", error);
    res.status(500).json({ error: "Error obteniendo documentos" });
  }
});

// ============================================
// ENDPOINT: HISTORIAL DE CONVERSACIONES
// ============================================
app.get("/history/:conversationId", async (req, res) => {
  try {
    const conversations = await Conversation.find({ 
      conversationId: req.params.conversationId 
    }).sort({ createdAt: 1 });

    res.json({ conversations });
  } catch (error) {
    console.error("Error obteniendo historial:", error);
    res.status(500).json({ error: "Error obteniendo historial" });
  }
});

// ============================================
// ENDPOINT: ESTADÍSTICAS
// ============================================
app.get("/stats", async (req, res) => {
  try {
    const totalConversations = await Conversation.countDocuments();
    const totalDocuments = await Document.countDocuments();
    const avgResponseTime = await Conversation.aggregate([
      { $group: { _id: null, avgTime: { $avg: "$responseTime" } } }
    ]);

    const last24h = await Conversation.countDocuments({
      createdAt: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) }
    });

    res.json({
      totalConversations,
      totalDocuments,
      avgResponseTime: avgResponseTime[0]?.avgTime || 0,
      conversationsLast24h: last24h
    });
  } catch (error) {
    console.error("Error obteniendo stats:", error);
    res.status(500).json({ error: "Error obteniendo estadísticas" });
  }
});

// ============================================
// INICIAR SERVIDOR
// ============================================
app.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════╗
║  🚀 Servidor corriendo en puerto ${PORT}  ║
║  📍 http://localhost:${PORT}            ║
║  📊 Application Insights: ${client ? 'ON' : 'OFF'}    ║
║  🗂️  Blob Storage: ${blobServiceClient ? 'ON' : 'OFF'}        ║
╚════════════════════════════════════════╝
  `);
});