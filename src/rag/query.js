const { ChromaClient } = require("chromadb");
const { OpenAIEmbeddings } = require("langchain/embeddings/openai");
const { ChatOpenAI } = require("langchain/chat_models/openai");
require("dotenv").config();

const client = new ChromaClient();
const collectionName = "empresa_info";

async function consultarEmpresa(pregunta) {
  const embeddings = new OpenAIEmbeddings({
    openAIApiKey: process.env.OPENAI_API_KEY,
  });

  const collection = await client.getCollection({ name: collectionName });

  const preguntaEmb = await embeddings.embedQuery(pregunta);

  const resultados = await collection.query({
    queryEmbeddings: [preguntaEmb],
    nResults: 3,
  });

  // Acá asumimos que resultados.documents es un array de arrays de strings
  const contexto = resultados.documents.flat().join("\n");

  const modelo = new ChatOpenAI({
    openAIApiKey: process.env.OPENAI_API_KEY,
    temperature: 0.4,
  });

  const prompt = `Sos un asistente de atención al cliente. Respondé en base a la siguiente información de la empresa:\n\n${contexto}\n\nPregunta: ${pregunta}`;

  const respuesta = await modelo.call([{ role: "user", content: prompt }]);

  return respuesta.text;
}

module.exports = { consultarEmpresa };
