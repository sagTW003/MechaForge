# Licencias de terceros

MechaForge incluye o usa estos componentes de terceros:

| Componente | Uso en MechaForge | Licencia |
|---|---|---|
| [Godot Engine](https://godotengine.org) 4.7.2 .NET | Motor del simulador | MIT |
| [.NET 8 runtime](https://dotnet.microsoft.com) | Va dentro del ejecutable (`data_MechaForge_windows_x86_64`) | MIT |
| [PDFium](https://pdfium.googlesource.com/pdfium/) | Lee los PDF adjuntos al chat de OpenClaw: texto y render de páginas (`pdfium.dll`) | BSD-3-Clause y Apache 2.0 (© The PDFium Authors) |
| [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) (`bblanchon.PDFium.Win32` en nuget.org) | Binarios compilados de PDFium | Apache 2.0 (© Benoît Blanchon) |
| [MediaPipe](https://github.com/google-ai-edge/mediapipe) (opcional) | Seguimiento de manos (`handtracking/`, se instala aparte con pip) | Apache 2.0 |

PDFium incorpora a su vez bibliotecas de terceros (FreeType, libjpeg-turbo, OpenJPEG,
zlib, lcms2, libpng, libtiff, abseil…). Todas tienen licencias permisivas; la lista y
los textos completos están en el repositorio de PDFium
(`third_party/*/LICENSE` en <https://pdfium.googlesource.com/pdfium/>) y en las
releases de pdfium-binaries.
