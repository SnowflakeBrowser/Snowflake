<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <Nullable>disable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>Veil</AssemblyName>
    <RootNamespace>Veil</RootNamespace>
    <StartupObject>Veil.Program</StartupObject>
    <ApplicationIcon>Assets\AppIcon.ico</ApplicationIcon>
    <Version>0.1.0</Version>
    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>
  </PropertyGroup>
  <ItemGroup>
    <Using Include="System.IO" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Web.WebView2" Version="1.0.2592.51" />
  </ItemGroup>
  <ItemGroup>
    <EmbeddedResource Include="Assets\*.js;Assets\*.css;Assets\*.json" LogicalName="%(Filename)%(Extension)" />
    <Resource Include="Assets\AppIcon.ico" />
  </ItemGroup>
</Project>
