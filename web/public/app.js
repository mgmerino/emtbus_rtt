// EMT Madrid Bus Tracker - Frontend Application

class BusTracker {
  constructor() {
    this.map = null;
    this.markers = [];
    this.stopMarker = null;
    this.arrivals = [];
    this.stopInfo = null;
    this.selectedBusId = null;
    this.currentStopId = null;
    this.currentLine = null;
    this.favorites = [];
    this.maxFavorites = 5;

    this.init();
  }

  init() {
    this.loadFavorites();
    this.initMap();
    this.bindEvents();
    this.renderFavorites();
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

    // Refresh button
    const refreshBtn = document.getElementById('refreshBtn');
    refreshBtn.addEventListener('click', () => {
      if (this.currentStopId) {
        this.fetchArrivals();
      }
    });

    // Favorite button
    const favoriteBtn = document.getElementById('favoriteBtn');
    favoriteBtn.addEventListener('click', () => {
      if (this.currentStopId) {
        this.toggleFavorite();
      }
    });
  }

  // Favorites management
  loadFavorites() {
    try {
      const stored = localStorage.getItem('emtbus_favorites');
      this.favorites = stored ? JSON.parse(stored) : [];
    } catch (e) {
      this.favorites = [];
    }
  }

  saveFavorites() {
    try {
      localStorage.setItem('emtbus_favorites', JSON.stringify(this.favorites));
    } catch (e) {
      console.error('Failed to save favorites:', e);
    }
  }

  isFavorite(stopId, line = null) {
    return this.favorites.some(f => f.stopId === stopId && f.line === line);
  }

  toggleFavorite() {
    const stopId = this.currentStopId;
    const line = this.currentLine;
    const stopName = this.stopInfo?.stopName || null;

    const existingIndex = this.favorites.findIndex(
      f => f.stopId === stopId && f.line === line
    );

    if (existingIndex >= 0) {
      // Remove from favorites
      this.favorites.splice(existingIndex, 1);
    } else {
      // Add to favorites (check limit)
      if (this.favorites.length >= this.maxFavorites) {
        alert(`Maximum ${this.maxFavorites} favorites allowed. Remove one first.`);
        return;
      }
      this.favorites.push({ stopId, line, stopName });
    }

    this.saveFavorites();
    this.renderFavorites();
    this.updateFavoriteButton();
  }

  removeFavorite(index) {
    this.favorites.splice(index, 1);
    this.saveFavorites();
    this.renderFavorites();
    this.updateFavoriteButton();
  }

  loadFavoriteStop(favorite) {
    document.getElementById('stopId').value = favorite.stopId;
    document.getElementById('line').value = favorite.line || '';
    this.fetchArrivals();
  }

  renderFavorites() {
    const section = document.getElementById('favoritesSection');
    const list = document.getElementById('favoritesList');
    const count = document.getElementById('favoritesCount');

    count.textContent = `${this.favorites.length}/${this.maxFavorites}`;

    if (this.favorites.length === 0) {
      section.style.display = 'none';
      return;
    }

    section.style.display = 'block';
    list.innerHTML = this.favorites.map((fav, index) => `
      <div class="favorite-chip" data-index="${index}">
        <span class="stop-id">${fav.stopId}</span>
        ${fav.stopName ? `<span class="stop-name">${fav.stopName}</span>` : ''}
        ${fav.line ? `<span class="line-filter">${fav.line}</span>` : ''}
        <span class="remove-btn" data-remove="${index}">&times;</span>
      </div>
    `).join('');

    // Add click handlers
    list.querySelectorAll('.favorite-chip').forEach(chip => {
      chip.addEventListener('click', (e) => {
        if (e.target.classList.contains('remove-btn')) {
          const removeIndex = parseInt(e.target.dataset.remove);
          this.removeFavorite(removeIndex);
        } else {
          const index = parseInt(chip.dataset.index);
          this.loadFavoriteStop(this.favorites[index]);
        }
      });
    });
  }

  updateFavoriteButton() {
    const btn = document.getElementById('favoriteBtn');
    const isFav = this.isFavorite(this.currentStopId, this.currentLine);
    btn.innerHTML = isFav ? '&#x2605;' : '&#x2606;'; // filled vs empty star
    btn.classList.toggle('active', isFav);
    btn.title = isFav ? 'Remove from favorites' : 'Save to favorites';
  }

  async fetchArrivals() {
    const stopId = document.getElementById('stopId').value.trim();
    const line = document.getElementById('line').value.trim() || null;
    const btn = document.getElementById('searchBtn');
    const refreshBtn = document.getElementById('refreshBtn');
    const favoriteBtn = document.getElementById('favoriteBtn');
    const listEl = document.getElementById('arrivalsList');

    if (!stopId) return;

    // Store current search params
    this.currentStopId = stopId;
    this.currentLine = line;

    // Show loading state
    btn.disabled = true;
    btn.textContent = 'Loading...';
    refreshBtn.disabled = true;
    refreshBtn.classList.add('spinning');
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

      // Enable action buttons
      refreshBtn.disabled = false;
      favoriteBtn.disabled = false;
      this.updateFavoriteButton();
    } catch (error) {
      listEl.innerHTML = `<div class="error-message">Error: ${error.message}</div>`;
      refreshBtn.disabled = false;
      favoriteBtn.disabled = true;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Track Buses';
      refreshBtn.classList.remove('spinning');
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
    this.stopInfo = responseData.StopInfo?.[0] || null;

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

    // Add stop marker if we have stop info
    if (this.stopInfo?.geometry?.coordinates) {
      const [lon, lat] = this.stopInfo.geometry.coordinates;
      if (lat && lon) {
        const stopIcon = this.createStopIcon(this.stopInfo.stopName || stopId);
        
        this.stopMarker = L.marker([lat, lon], { icon: stopIcon, zIndexOffset: 1000 })
          .addTo(this.map)
          .bindPopup(this.createStopPopupContent(this.stopInfo));

        bounds.push([lat, lon]);
      }
    }

    // Add bus markers
    this.arrivals.forEach(arrival => {
      if (!arrival.geometry?.coordinates) return;

      const [lon, lat] = arrival.geometry.coordinates;
      if (!lat || !lon) return;

      const icon = this.createBusIcon(arrival.line);
      
      const marker = L.marker([lat, lon], { icon })
        .addTo(this.map)
        .bindPopup(this.createPopupContent(arrival));

      marker.busId = String(arrival.bus);
      marker.on('click', () => this.selectBus(marker.busId));

      this.markers.push(marker);
      bounds.push([lat, lon]);
    });

    // Fit bounds to show stop and all buses
    if (bounds.length > 0) {
      const allMarkers = this.stopMarker 
        ? [this.stopMarker, ...this.markers]
        : this.markers;
      const group = L.featureGroup(allMarkers);
      this.map.fitBounds(group.getBounds().pad(0.2));
    }
  }

  createStopIcon(stopName) {
    return L.divIcon({
      className: 'stop-marker',
      html: `
        <div style="
          color: #fff;
          font-family: 'Space Grotesk', sans-serif;
          font-weight: 600;
          font-size: 11px;
          padding: 6px 10px;
          border-radius: 35px;
          box-shadow: 0 3px 15px rgba(255, 239, 107, 0.5);
          white-space: nowrap;
          display: flex;
          align-items: center;
          gap: 5px;
        ">
          <span style="font-size: 32px;">🚏</span>
        </div>
      `,
      iconSize: [60, 36],
      iconAnchor: [60, 36]
    });
  }

  createStopPopupContent(stopInfo) {
    const lines = stopInfo.lines || [];
    const linesHtml = lines.map(l => `
      <span class="popup-line" style="background: #${l.color || '0072ce'}; ${l.forecolor ? 'color: #' + l.forecolor : ''}">${l.label}</span>
    `).join(' ');

    return `
      <div class="popup-title">
        <span style="font-size: 22px;">🚏</span>
        ${stopInfo.stopName || 'Bus Stop'}
      </div>
      <div class="popup-detail"><strong>Stop ID:</strong> ${stopInfo.stopId}</div>
      <div class="popup-detail">${stopInfo.Direction || ''}</div>
      <div style="margin-top: 8px;">${linesHtml}</div>
    `;
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
    this.stopInfo = null;
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

