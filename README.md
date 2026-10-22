# PAP — Paper AirPlane

Godot 기반 Paper AirPlane 프로젝트입니다.

## 개발 환경

- Godot 4.7.1 .NET
- 시작 씬: `scenes/main.tscn`
- 렌더러: Compatibility

## 실행

Godot 프로젝트 매니저에서 `project.godot`을 가져온 뒤 F6으로 현재 씬을,
F5로 프로젝트를 실행합니다.

설치된 Godot을 PowerShell에서 직접 실행할 수도 있습니다.

```powershell
& 'D:\Works\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe' --editor --path 'D:\Works\Git\PAP'
```

현재 시작 씬은 빈 `Node`입니다. 게임 방향에 맞춰 2D 또는 3D 씬과
GDScript 또는 C# 스크립트를 추가하면 됩니다. C# 사용 시 Godot 버전에
맞는 .NET SDK가 필요합니다.

## Git

기본 브랜치는 `main`입니다. `.godot/` 캐시, 내보낸 빌드, .NET 빌드 산출물은
추적하지 않습니다. Godot이 생성하는 `.uid` 및 `.import` 파일은 커밋합니다.
원격 저장소는 아직 연결하지 않았습니다.
