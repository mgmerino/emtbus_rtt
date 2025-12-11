// EMT Madrid Bus Tracker - Frontend Application

class BusTracker {
  constructor() {
    this.map = null;
    this.markers = [];
    this.stopMarker = null;
    this.arrivals = [];
    this.selectedBusId = null;
    
    this.init();
  }

  init() {
    this.initMap();
    this.bindEvents();
  }

  initMap() {
    // Center on Madrid
    this.map = L.map('map', {
      zoomControl: true,
      attributionControl: true
    }).setView([40.4168, -3.7038], 13);

    // Add dark tile layer (CartoDB Dark Matter)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      maxZoom: 19
    }).addTo(this.map);
  }

  bindEvents() {
    const form = document.getElementById('searchForm');
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      this.fetchArrivals();
    });
  }

  async fetchArrivals() {
    const stopId = document.getElementById('stopId').value.trim();
    const line = document.getElementById('line').value.trim() || null;
    const btn = document.getElementById('searchBtn');
    const listEl = document.getElementById('arrivalsList');

    if (!stopId) return;

    // Show loading state
    btn.disabled = true;
    btn.textContent = 'Loading...';
    listEl.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

    try {
      const params = new URLSearchParams({ stop_id: stopId });
      if (line) params.append('line', line);

      const response = await fetch(`/api/arrivals?${params}`);
      const data = await response.json();

      if (data.error) {
        throw new Error(data.error);
      }

      this.processArrivals(data, stopId);
    } catch (error) {
      listEl.innerHTML = `<div class="error-message">Error: ${error.message}</div>`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Track Buses';
    }
  }

  processArrivals(data, stopId) {
    // Clear existing markers
    this.clearMarkers();

    if (data.code !== '00' || !data.data?.[0]) {
      this.showEmpty('No data available for this stop.');
      return;
    }

    const responseData = data.data[0];
    this.arrivals = responseData.Arrive || [];

    if (this.arrivals.length === 0) {
      this.showEmpty('No buses arriving at this stop.');
      return;
    }

    // Update UI
    this.renderArrivals();
    this.renderMap(stopId);

    // Update count
    document.getElementById('arrivalCount').textContent = this.arrivals.length;
  }

  renderArrivals() {
    const listEl = document.getElementById('arrivalsList');
    
    // Sort by ETA
    const sorted = [...this.arrivals].sort((a, b) => a.estimateArrive - b.estimateArrive);

    listEl.innerHTML = sorted.map(arrival => this.createArrivalCard(arrival)).join('');

    // Add click handlers
    listEl.querySelectorAll('.arrival-card').forEach(card => {
      card.addEventListener('click', () => {
        const busId = card.dataset.busId;
        this.selectBus(busId);
      });
    });
  }

  createArrivalCard(arrival) {
    const eta = this.formatEta(arrival.estimateArrive);
    const etaClass = this.getEtaClass(arrival.estimateArrive);
    const distance = this.formatDistance(arrival.DistanceBus);
    const isActive = this.selectedBusId === String(arrival.bus) ? 'active' : '';

    return `
      <div class="arrival-card ${isActive}" data-bus-id="${arrival.bus}">
        <div class="arrival-header">
          <span class="line-badge">${arrival.line}</span>
          <div class="eta">
            <div class="eta-time ${etaClass}">${eta}</div>
            <div class="eta-label">ETA</div>
          </div>
        </div>
        <div class="arrival-details">
          <div class="detail">
            <span class="detail-label">Bus #</span>
            <span class="detail-value">${arrival.bus}</span>
          </div>
          <div class="detail">
            <span class="detail-label">Distance</span>
            <span class="detail-value">${distance}</span>
          </div>
          <div class="detail destination">
            <span class="detail-label">Destination</span>
            <span class="detail-value">${arrival.destination}</span>
          </div>
        </div>
      </div>
    `;
  }

  renderMap(stopId) {
    const bounds = [];

    // Add bus markers
    this.arrivals.forEach(arrival => {
      if (!arrival.geometry?.coordinates) return;

      const [lon, lat] = arrival.geometry.coordinates;
      if (!lat || !lon) return;

      const eta = this.formatEta(arrival.estimateArrive);
      const icon = this.createBusIcon(arrival.line);
      
      const marker = L.marker([lat, lon], { icon })
        .addTo(this.map)
        .bindPopup(this.createPopupContent(arrival));

      marker.busId = String(arrival.bus);
      marker.on('click', () => this.selectBus(marker.busId));

      this.markers.push(marker);
      bounds.push([lat, lon]);
    });

    // Try to get stop location from first arrival or use average of bus positions
    if (bounds.length > 0) {
      // Add a stop marker at estimated position (we don't have exact stop coords in arrivals)
      // For now, fit bounds to show all buses
      const group = L.featureGroup(this.markers);
      this.map.fitBounds(group.getBounds().pad(0.2));
    }
  }

  createBusIcon(line) {
    return L.divIcon({
      className: 'bus-marker',
      html: `
        <div style="
          background: linear-gradient(135deg, #00d4aa, #00a88a);
          color: #0a0a0f;
          font-family: 'JetBrains Mono', monospace;
          font-weight: 600;
          font-size: 12px;
          padding: 4px 8px;
          border-radius: 6px;
          box-shadow: 0 2px 10px rgba(0, 212, 170, 0.4);
          white-space: nowrap;
          display: flex;
          align-items: center;
          gap: 4px;
        ">
          <span style="font-size: 14px;">🚌</span>
          ${line}
        </div>
      `,
      iconSize: [60, 30],
      iconAnchor: [30, 15]
    });
  }

  createPopupContent(arrival) {
    const eta = this.formatEta(arrival.estimateArrive);
    const distance = this.formatDistance(arrival.DistanceBus);

    return `
      <div class="popup-title">
        <span class="popup-line">${arrival.line}</span>
        Bus #${arrival.bus}
      </div>
      <div class="popup-eta">${eta}</div>
      <div class="popup-detail">${distance} away</div>
      <div class="popup-detail">→ ${arrival.destination}</div>
    `;
  }

  selectBus(busId) {
    this.selectedBusId = busId;

    // Update card styles
    document.querySelectorAll('.arrival-card').forEach(card => {
      card.classList.toggle('active', card.dataset.busId === busId);
    });

    // Open popup on marker
    const marker = this.markers.find(m => m.busId === busId);
    if (marker) {
      this.map.setView(marker.getLatLng(), 15);
      marker.openPopup();
    }
  }

  clearMarkers() {
    this.markers.forEach(marker => this.map.removeLayer(marker));
    this.markers = [];
    if (this.stopMarker) {
      this.map.removeLayer(this.stopMarker);
      this.stopMarker = null;
    }
    this.selectedBusId = null;
  }

  showEmpty(message) {
    document.getElementById('arrivalsList').innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">🚌</div>
        <h3>No buses found</h3>
        <p>${message}</p>
      </div>
    `;
    document.getElementById('arrivalCount').textContent = '0';
  }

  formatEta(seconds) {
    if (seconds <= 0) return 'Now';
    if (seconds < 60) return `${seconds}s`;
    
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    
    if (remainingSeconds === 0) return `${minutes}m`;
    return `${minutes}m ${remainingSeconds}s`;
  }

  getEtaClass(seconds) {
    if (seconds <= 60) return 'arriving';
    if (seconds <= 300) return 'soon';
    return '';
  }

  formatDistance(meters) {
    if (meters <= 0) return 'At stop';
    if (meters < 1000) return `${meters}m`;
    return `${(meters / 1000).toFixed(1)}km`;
  }
}

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
  window.busTracker = new BusTracker();
});

