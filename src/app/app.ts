import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import {Map}  from './Maps/map/map';
@Component({
  selector: 'app-root',
  imports: [RouterOutlet, Map],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  protected readonly title = signal('Ubik');
}
