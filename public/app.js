document.addEventListener('DOMContentLoaded', () => {
  const btnRunSim = document.getElementById('btnRunSim');
  const btnRun50x = document.getElementById('btnRun50x');
  const btnToggleOutage = document.getElementById('btnToggleOutage');
  const btnReset = document.getElementById('btnReset');

  const valIngress = document.getElementById('valIngress');
  const valEdgeDropped = document.getElementById('valEdgeDropped');
  const valStock = document.getElementById('valStock');
  const valReservations = document.getElementById('valReservations');
  const valPaySuccess = document.getElementById('valPaySuccess');
  const valPayFail = document.getElementById('valPayFail');
  const valKafka = document.getElementById('valKafka');
  const valOrders = document.getElementById('valOrders');
  const valDuplicates = document.getElementById('valDuplicates');
  const systemStatus = document.getElementById('systemStatus');
  const kafkaSubtext = document.getElementById('kafkaSubtext');
  const terminalLogs = document.getElementById('terminalLogs');

  async function fetchStatus() {
    try {
      const res = await fetch('/api/status');
      const state = await res.json();
      updateUI(state);
    } catch (err) {
      console.error('Failed to fetch simulation status:', err);
    }
  }

  function updateUI(state) {
    valIngress.textContent = state.ingressRequests.toLocaleString();
    valEdgeDropped.textContent = state.edgeDropped.toLocaleString();
    valStock.textContent = state.stock.toLocaleString();
    valReservations.textContent = state.reservationsCreated.toLocaleString();
    valPaySuccess.textContent = state.paymentsSucceeded.toLocaleString();
    valPayFail.textContent = state.paymentsFailed.toLocaleString();
    valKafka.textContent = state.kafkaBufferedMessages.toLocaleString();
    valOrders.textContent = state.ordersCreated.toLocaleString();
    valDuplicates.textContent = state.duplicateRequestsHandled.toLocaleString();

    if (state.orderServiceDown) {
      systemStatus.textContent = `ORDER SVC OUTAGE (${state.outageTimeRemaining}s)`;
      systemStatus.className = 'badge badge-red';
      kafkaSubtext.textContent = '⚠️ BUFFERING IN KAFKA (Order Svc Down)';
      kafkaSubtext.style.color = '#f87171';
    } else {
      systemStatus.textContent = 'SYSTEM READY';
      systemStatus.className = 'badge badge-green';
      kafkaSubtext.textContent = 'Buffered Outbox Events';
      kafkaSubtext.style.color = '#64748b';
    }

    // Render Logs
    terminalLogs.innerHTML = '';
    state.logs.forEach(log => {
      const div = document.createElement('div');
      div.className = `log-line log-${log.type}`;
      div.textContent = `[${log.timestamp}] ${log.message}`;
      terminalLogs.appendChild(div);
    });
    terminalLogs.scrollTop = terminalLogs.scrollHeight;
  }

  btnRunSim.addEventListener('click', async () => {
    btnRunSim.disabled = true;
    try {
      const res = await fetch('/api/simulate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ users: 10000, duplicatePercent: 0.02 })
      });
      const data = await res.json();
      updateUI(data.state);
    } catch (err) {
      console.error(err);
    } finally {
      btnRunSim.disabled = false;
    }
  });

  btnRun50x.addEventListener('click', async () => {
    btnRun50x.disabled = true;
    try {
      const res = await fetch('/api/simulate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ users: 10000, duplicatePercent: 0.02, is50xBurst: true })
      });
      const data = await res.json();
      updateUI(data.state);
    } catch (err) {
      console.error(err);
    } finally {
      btnRun50x.disabled = false;
    }
  });

  btnToggleOutage.addEventListener('click', async () => {
    try {
      const res = await fetch('/api/outage', { method: 'POST' });
      const data = await res.json();
      updateUI(data.state);
    } catch (err) {
      console.error(err);
    }
  });

  btnReset.addEventListener('click', async () => {
    try {
      const res = await fetch('/api/reset', { method: 'POST' });
      const data = await res.json();
      updateUI(data.state);
    } catch (err) {
      console.error(err);
    }
  });

  // Initial fetch and 1-second status polling loop
  fetchStatus();
  setInterval(fetchStatus, 1000);
});
