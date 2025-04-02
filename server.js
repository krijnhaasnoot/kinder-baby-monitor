const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { v4: uuidv4 } = require('uuid');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*"
  }
});

// ✅ Voeg een eenvoudige route toe zodat Railway iets teruggeeft op GET /
app.get("/", (req, res) => {
  res.send("✅ Signaling Server draait via Railway!");
});

// 👥 Geheugen voor actieve connecties en status
const activePairs = {}; // { pairingCode: { monitorId, viewerId } }
const monitoringStatusByCode = {}; // { pairingCode: true/false }

io.on('connection', (socket) => {
  console.log('📡 New socket connected:', socket.id);

  // 🔢 Genereer een unieke code voor pairing
  socket.on('generateCode', () => {
    const code = Math.floor(100000 + Math.random() * 900000).toString(); // 6-digit
    activePairs[code] = { monitorId: socket.id };
    socket.emit('codeGenerated', code);
    console.log(`🔐 Code ${code} assigned to monitor ${socket.id}`);
  });

  // 👁️ Viewer probeert te koppelen met een code
  socket.on('joinWithCode', (code) => {
    const pair = activePairs[code];
    if (pair && !pair.viewerId) {
      pair.viewerId = socket.id;
      socket.emit('pairingSuccess');
      io.to(pair.monitorId).emit('viewerJoined');
      console.log(`✅ Viewer ${socket.id} joined monitor ${pair.monitorId}`);
    } else {
      socket.emit('pairingFailed');
    }
  });

  // 🔁 Signaling events
  socket.on('offer', (data) => {
    const pair = findPairBySocketId(socket.id);
    if (pair) {
      const target = socket.id === pair.monitorId ? pair.viewerId : pair.monitorId;
      io.to(target).emit('offer', data);
    }
  });

  socket.on('answer', (data) => {
    const pair = findPairBySocketId(socket.id);
    if (pair) {
      const target = socket.id === pair.monitorId ? pair.viewerId : pair.monitorId;
      io.to(target).emit('answer', data);
    }
  });

  socket.on('candidate', (data) => {
    const pair = findPairBySocketId(socket.id);
    if (pair) {
      const target = socket.id === pair.monitorId ? pair.viewerId : pair.monitorId;
      io.to(target).emit('candidate', data);
    }
  });

  // 🎯 Monitoring status (bijv. start/stop monitoring)
  socket.on('monitoringStatus', (isActive) => {
    const pair = findPairBySocketId(socket.id);
    if (pair) {
      const code = findCodeBySocketId(socket.id);
      if (code) {
        monitoringStatusByCode[code] = isActive;
      }

      const target = socket.id === pair.monitorId ? pair.viewerId : pair.monitorId;
      io.to(target).emit('monitoringStatus', isActive);
      console.log(`🟢 Monitoring status ${isActive} sent to ${target}`);
    }
  });

  // 🔍 Viewer vraagt expliciet om de huidige monitoring status
  socket.on('requestMonitoringStatus', () => {
    const code = findCodeBySocketId(socket.id);
    const status = monitoringStatusByCode[code] || false;
    socket.emit('monitoringStatus', status);
    console.log(`📨 Sent current monitoringStatus (${status}) to ${socket.id}`);
  });

  // 🛑 Handle disconnects
  socket.on('disconnect', () => {
    for (const code in activePairs) {
      const pair = activePairs[code];
      if (pair.monitorId === socket.id || pair.viewerId === socket.id) {
        delete activePairs[code];
        delete monitoringStatusByCode[code];
        console.log(`❌ Pair with code ${code} removed due to disconnect`);
        break;
      }
    }
  });
});

// 🔍 Helpers
function findPairBySocketId(id) {
  for (const code in activePairs) {
    const pair = activePairs[code];
    if (pair.monitorId === id || pair.viewerId === id) {
      return pair;
    }
  }
  return null;
}

function findCodeBySocketId(id) {
  for (const code in activePairs) {
    const pair = activePairs[code];
    if (pair.monitorId === id || pair.viewerId === id) {
      return code;
    }
  }
  return null;
}

// 🚀 Start de server
const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
