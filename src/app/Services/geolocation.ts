import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export interface Coords {
  lat: number,
  lng: number,
  accuracy: number
}

@Injectable({
  providedIn: 'root',
})
export class Geolocation {
  
  constructor() { }
  
  watchLocation(): Observable<Coords> { 
    return new Observable(observer => {
      
      if (!navigator.geolocation) {
        observer.error(new Error('El navegador no soporta geolocalizacion'));
        return; 
      }

      const options: PositionOptions = {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0 
      };

      let watchId: number; 

      watchId = navigator.geolocation.watchPosition(
        (position) => {
          const coords: Coords = {
            lat: position.coords.latitude,
            lng: position.coords.longitude,
            accuracy: position.coords.accuracy
          };
          
          observer.next(coords); 
          
        },
        (error) => {
          console.error('[Servicio] Error en watchPosition:', error.message);
          observer.error(error); 
        },
        options
      );
      
      return () => {
        console.log('[Servicio] Deteniendo watchPosition. ID:', watchId);
        navigator.geolocation.clearWatch(watchId);
      };
    });
  }
}