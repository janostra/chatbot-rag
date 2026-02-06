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
import { SecretClient } from "@azure/keyvault-secrets";
import { DefaultAzureCredential } from "@azure/identity";
import crypto from 'crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// ============================================
// KEY VAULT SETUP
// ============================================
let secrets = {};

async function loadSecretsFromKeyVault() {
  try {
    if (process.env.VAULT_URL) {
      console.log("🔐 Cargando secrets desde Key Vault...");
      
      const credential = new DefaultAzureCredential();
      const client = new SecretClient(process.env.VAULT_URL, credential);
      
      secrets.MONGO_URI = (await client.getSecret("MONGO-URI")).value;
      secrets.SPEECH_KEY = (await client.getSecret("SPEECH-KEY")).value;
      secrets.AZURE_SEARCH_KEY = (await client.getSecret("AZURE-SEARCH-KEY")).value;
      secrets.HUGGINGFACE_API_KEY = (await client.getSecret("HUGGINGFACE-API-KEY")).value;
      secrets.STORAGE_CONNECTION = (await client.getSecret("STORAGE-CONNECTION")).value;
      
      console.log("✅ Secrets cargados desde Key Vault");
    } else {
      // Fallback a variables de entorno
      console.log("⚠️  Key Vault no configurado, usando .env");
      secrets.MONGO_URI = process.env.MONGO_URI;
      secrets.SPEECH_KEY = process.env.SPEECH_KEY;
      secrets.AZURE_SEARCH_KEY = process.env.AZURE_SEARCH_KEY;
      secrets.HUGGINGFACE_API_KEY = process.env.HUGGINGFACE_API_KEY;
      secrets.STORAGE_CONNECTION = process.env.AZURE_STORAGE_CONNECTION_STRING;
    }
  } catch (error) {
    console.error("❌ Error cargando secrets:", error);
    process.exit(1);
  }
}

await loadSecretsFromKeyVault();

// ============================================
// APPLICATION INSIGHTS
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
// BLOB STORAGE
// ============================================
let blobServiceClient;
if (secrets.STORAGE_CONNECTION) {
  blobServiceClient = BlobServiceClient.fromConnectionString(secrets.STORAGE_CONNECTION);
  console.log("✅ Blob Storage configurado");
}

// ============================================
// MULTER
// ============================================
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }
});

// ============================================
// CONEXIÓN COSMOS DB
// ============================================
mongoose.connect(secrets.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
}).then(() => {
  console.log("✅ Conectado a Cosmos DB");
  if (client) client.trackEvent({ name: "DatabaseConnected" });
}).catch(err => {
  console.error("❌ Error conectando a Cosmos DB:", err);
  if (client) client.trackException({ exception: err });
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
// ADMIN AUTH
// ============================================
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || "admin";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "changeme123";

const adminTokens = new Map();

function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}

function verifyAdminToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No autorizado' });
  }

  const token = authHeader.substring(7);
  
  if (!adminTokens.has(token)) {
    return res.status(401).json({ error: 'Token inválido' });
  }

  next();
}

// ============================================
// ROUTES - PUBLIC
// ============================================

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.get("/admin", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "admin.html"));
});

app.get("/health", (req, res) => {
  const health = {
    status: "ok",
    timestamp: new Date().toISOString(),
    services: {
      database: mongoose.connection.readyState === 1 ? "connected" : "disconnected",
      blobStorage: blobServiceClient ? "configured" : "not configured",
      appInsights: client ? "active" : "not configured",
      rag: process.env.RAG_ENDPOINT ? "configured" : "not configured",
      keyVault: process.env.VAULT_URL ? "configured" : "not configured"
    }
  };
  
  res.json(health);
});

// ============================================
// ADMIN LOGIN
// ============================================
app.post("/admin/login", (req, res) => {
  const { username, password } = req.body;
  
  if (username === ADMIN_USERNAME && password === ADMIN_PASSWORD) {
    const token = generateToken();
    adminTokens.set(token, { username, loginTime: Date.now() });
    
    if (client) {
      client.trackEvent({ name: "AdminLogin", properties: { username } });
    }
    
    res.json({ success: true, token });
  } else {
    res.status(401).json({ success: false, error: "Credenciales incorrectas" });
  }
});

// ============================================
// CHAT - PUBLIC
// ============================================
app.post("/ask", async (req, res) => {
  const startTime = Date.now();
  const { query, conversationId = `conv_${Date.now()}`, userId = "anonymous" } = req.body;
  
  if (!query || query.trim() === "") {
    return res.status(400).json({ error: "La pregunta no puede estar vacía" });
  }

  try {
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

    await Conversation.create({ 
      conversationId,
      userId,
      question: query, 
      answer: answer,
      responseTime
    });

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
        measurements: { responseTime }
      });

      client.trackMetric({ name: "ResponseTime", value: responseTime });
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
        properties: { endpoint: "/ask", query: query.substring(0, 50) }
      });
    }
    
    res.status(500).json({ 
      error: "Error procesando tu pregunta",
      details: process.env.NODE_ENV === "development" ? err.message : undefined
    });
  }
});

// ============================================
// SPEECH-TO-TEXT - PUBLIC
// ============================================
app.post("/stt", async (req, res) => {
  const startTime = Date.now();
  
  try {
    const { audioData } = req.body;
    
    if (!audioData) {
      return res.status(400).json({ error: "No se recibió audio" });
    }

    const speechConfig = sdk.SpeechConfig.fromSubscription(
      secrets.SPEECH_KEY,
      process.env.SPEECH_REGION
    );
    
    speechConfig.speechRecognitionLanguage = "es-AR";

    const audioBuffer = Buffer.from(audioData, 'base64');
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
              measurements: { responseTime }
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
        if (client) client.trackException({ exception: error });
        res.status(500).json({ error: "Error en reconocimiento de voz" });
        recognizer.close();
      }
    );

  } catch (error) {
    console.error("Error general STT:", error);
    if (client) client.trackException({ exception: error });
    res.status(500).json({ error: "Error en el servicio de voz" });
  }
});

// ============================================
// TEXT-TO-SPEECH - PUBLIC
// ============================================
app.post("/tts", async (req, res) => {
  const startTime = Date.now();
  const { text } = req.body;
  
  if (!text || text.trim() === "") {
    return res.status(400).json({ error: "El texto no puede estar vacío" });
  }

  try {
    const speechConfig = sdk.SpeechConfig.fromSubscription(
      secrets.SPEECH_KEY,
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
              properties: { textLength: text.length, success: true },
              measurements: { responseTime, audioSize: audioData.byteLength }
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
        if (client) client.trackException({ exception: err });
        synthesizer.close();
        res.status(500).json({ error: "Error al convertir voz" });
      }
    );
  } catch (error) {
    console.error("Error general TTS:", error);
    if (client) client.trackException({ exception: error });
    res.status(500).json({ error: "Error en el servicio de voz" });
  }
});

// ============================================
// ADMIN ROUTES - PROTECTED
// ============================================

app.post("/admin/upload-document", verifyAdminToken, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: "No se recibió archivo" });
    }

    if (!blobServiceClient) {
      return res.status(503).json({ error: "Blob Storage no configurado" });
    }

    const documentId = uuidv4();
    const filename = `${documentId}-${req.file.originalname}`;
    
    const containerClient = blobServiceClient.getContainerClient("documents");
    await containerClient.createIfNotExists({ access: 'blob' });
    
    const blockBlobClient = containerClient.getBlockBlobClient(filename);
    await blockBlobClient.upload(req.file.buffer, req.file.buffer.length);

    const blobUrl = blockBlobClient.url;

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

    res.json({ 
      success: true, 
      documentId,
      filename: req.file.originalname,
      blobUrl,
      message: "Documento subido. Azure Function lo indexará automáticamente."
    });

  } catch (error) {
    console.error("Error subiendo documento:", error);
    if (client) client.trackException({ exception: error });
    res.status(500).json({ error: "Error subiendo documento" });
  }
});

app.get("/admin/documents", verifyAdminToken, async (req, res) => {
  try {
    const documents = await Document.find()
      .limit(50);
    
    res.json({ documents });
  } catch (error) {
    console.error("Error listando documentos:", error);
    res.status(500).json({ error: "Error obteniendo documentos" });
  }
});

app.delete("/admin/documents/:documentId", verifyAdminToken, async (req, res) => {
  try {
    const doc = await Document.findOne({ documentId: req.params.documentId });
    
    if (!doc) {
      return res.status(404).json({ error: "Documento no encontrado" });
    }

    // Eliminar de Blob Storage
    if (blobServiceClient && doc.blobUrl) {
      const containerClient = blobServiceClient.getContainerClient("documents");
      const blobName = doc.blobUrl.split('/').pop();
      const blockBlobClient = containerClient.getBlockBlobClient(blobName);
      await blockBlobClient.deleteIfExists();
    }

    // Eliminar de DB
    await Document.deleteOne({ documentId: req.params.documentId });

    if (client) {
      client.trackEvent({
        name: "DocumentDeleted",
        properties: { documentId: req.params.documentId }
      });
    }

    res.json({ success: true });
  } catch (error) {
    console.error("Error eliminando documento:", error);
    res.status(500).json({ error: "Error eliminando documento" });
  }
});

app.get("/admin/stats", verifyAdminToken, async (req, res) => {
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
// START SERVER
// ============================================
app.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════╗
║  🚀 Servidor corriendo en puerto ${PORT}  ║
║  📍 http://localhost:${PORT}            ║
║  🔐 Admin: http://localhost:${PORT}/admin ║
║  📊 Application Insights: ${client ? 'ON' : 'OFF'}    ║
║  🗂️  Blob Storage: ${blobServiceClient ? 'ON' : 'OFF'}        ║
║  🔑 Key Vault: ${process.env.VAULT_URL ? 'ON' : 'OFF'}          ║
╚════════════════════════════════════════╝
  `);
});