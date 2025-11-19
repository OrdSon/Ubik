import { Component, AfterViewInit, OnDestroy } from '@angular/core';
import { Geolocation, Coords } from '../../Services/geolocation';
import { Subscription } from 'rxjs';
import * as L from 'leaflet';
import "leaflet/dist/images/marker-shadow.png";
import "leaflet/dist/images/marker-icon-2x.png";


@Component({
  selector: 'app-map',
  imports: [],
  templateUrl: './map.html',
  styleUrl: './map.css',
})
export class Map implements AfterViewInit, OnDestroy {

  private locationSubscription!: Subscription;
  MAX_ACCEPTABLE_ACCURACY = 50000;

  ngAfterViewInit(): void {
    this.initMap();
    this.locateUser();
  }

  private map!: L.Map;
  private userMarker: L.Marker | null = null;
  private accuracyCircle: L.Circle | null = null; 
  private isFirstLocation: boolean = true;      

  constructor(private geolocationService: Geolocation) { }

  private initMap() {
    this.map = L.map('map', {
      center: [14.833333, -91.516667],
      zoom: 10
    });

    const tiles = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 25,
      minZoom: 7,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    });

    tiles.addTo(this.map);
    L.control.scale({ position: 'bottomleft' }).addTo(this.map);

  }

  private locateUser() {
    this.locationSubscription = this.geolocationService.watchLocation()
      .subscribe({
        next: (coords: Coords) => {
          console.log('Ubicacion actual', coords);

          if (coords.accuracy > this.MAX_ACCEPTABLE_ACCURACY) {
            console.warn(`⚠️ Precisión rechazada por ser demasiado grande (${coords.accuracy.toFixed(0)}m). Usando fallback.`);
            this.handleFallback(); // Llamada a fallback si la precisión es terrible
            return;
          }
          if (this.map) {
            const latLng = new L.LatLng(coords.lat, coords.lng);
            this.map.flyTo([coords.lat, coords.lng], 16);
            if (this.userMarker) {
              this.userMarker.setLatLng(latLng)
                .setPopupContent(`Tú (±${Math.round(coords.accuracy)}m)`);
            } else {
              this.userMarker = L.marker(latLng)
                .addTo(this.map)
                .bindPopup(`Tú (±${Math.round(coords.accuracy)}m)`).openPopup();
            }

            if (this.accuracyCircle) {
              this.accuracyCircle.setLatLng(latLng);
              this.accuracyCircle.setRadius(coords.accuracy);
            } else {
              this.accuracyCircle = L.circle(latLng, {
                color: '#136aec', fillOpacity: 0.15, radius: coords.accuracy
              }).addTo(this.map);
            }
            //Ajustar zoom 
            if (this.isFirstLocation) {
              this.map.flyToBounds(this.accuracyCircle.getBounds(), {
                padding: [50, 50],
                maxZoom: 18,
                duration: 1.5
              });
              this.isFirstLocation = false;
            } else {
              this.map.panTo(latLng, { duration: 0.5 }); 
            }
          }
        },
        error: (err: any) => {
          console.error('error obteniendo la ubicacion', err.message);

          if (err.code === 3) {
            console.warn('Timeout, se acabo el tiempo')
            //falta logica de fallback
          }
        },
        complete: () => {
          console.log('geolocalizacion completa')
        }
      });
  }

  private handleFallback() {
    const FALLBACK_ZOOM = 12;
    if (this.map) {
      this.map.setView([14.8, -91], FALLBACK_ZOOM);
      if (!this.userMarker) {
        L.marker([14.8, -91])
          .addTo(this.map)
          .bindPopup('No se pudo obtener la ubicación precisa.')
          .openPopup();
      }
    }
  }

  ngOnDestroy(): void {
    if (this.locationSubscription) {
      this.locationSubscription.unsubscribe();
    }
  }
  /*
    private locateUser(){
      if(!navigator.geolocation){
        console.error("No se pudo iniciar la geolocalización");
        return;
      }
      
    navigator.geolocation.getCurrentPosition(
        (position) => {
          const coords = {
            lat: position.coords.latitude,
            lng: position.coords.longitude
          };
  
      console.log('Ubicacion actual', coords);    
  
      if(this.map){
        this.map.flyTo([coords.lat, coords.lng], 16);
  
        if (this.userMarker) {
            this.userMarker.setLatLng([coords.lat, coords.lng]);
          } else {
            this.userMarker = L.marker([coords.lat, coords.lng])
              .addTo(this.map)
              .bindPopup('Estas aqui')
              .openPopup();
          }
      }
  
      },
      (error) => {
          console.error('Error al obtener la ubicación:', error.message);
          alert('No se pudo obtener tu ubicación.');        
        },
        {
          enableHighAccuracy: true,
          timeout:10000,
          maximumAge: 0
        }
      );
    }
  */


  private fullScreen() {

  }

}
