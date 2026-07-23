//! 生成可被 PowerPoint / WPS 打开的 .pptx（OOXML zip，零依赖外部 Office）。

use std::fs::File;
use std::io::{Cursor, Read, Write};
use std::path::Path;

use anyhow::{Context, Result};
use zip::write::SimpleFileOptions;
use zip::CompressionMethod;
use zip::ZipArchive;
use zip::ZipWriter;

fn options() -> SimpleFileOptions {
    // Office / WPS 对 Deflate 友好；避免 Zip64 扩展。
    SimpleFileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .large_file(false)
}

fn write_entry(zip: &mut ZipWriter<File>, name: &str, data: &str) -> Result<()> {
    zip.start_file(name, options())
        .with_context(|| format!("无法写入 pptx 条目：{name}"))?;
    zip.write_all(data.as_bytes())?;
    Ok(())
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn grp_sp_pr() -> &'static str {
    r#"<p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>"#
}

fn shape_box(id: u32, name: &str, x: i64, y: i64, cx: i64, cy: i64, body: &str) -> String {
    format!(
        r#"<p:sp>
        <p:nvSpPr>
          <p:cNvPr id="{id}" name="{name}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="{x}" y="{y}"/>
            <a:ext cx="{cx}" cy="{cy}"/>
          </a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
          <a:ln><a:noFill/></a:ln>
        </p:spPr>
        <p:txBody>
          <a:bodyPr wrap="square" rtlCol="0" anchor="t"/>
          <a:lstStyle/>
          {body}
        </p:txBody>
      </p:sp>"#
    )
}

fn slide_xml(title: &str, body: &str) -> String {
    let mut shapes = String::new();
    let mut next_id = 2u32;

    if !title.is_empty() {
        let para = format!(
            r#"<a:p>
            <a:pPr algn="l"/>
            <a:r>
              <a:rPr lang="zh-CN" altLang="en-US" sz="3200" b="1" dirty="0">
                <a:latin typeface="Microsoft YaHei"/>
                <a:ea typeface="Microsoft YaHei"/>
              </a:rPr>
              <a:t>{}</a:t>
            </a:r>
            <a:endParaRPr lang="zh-CN" sz="3200"/>
          </a:p>"#,
            xml_escape(title)
        );
        shapes.push_str(&shape_box(
            next_id,
            "Title 1",
            457200,
            274638,
            8229600,
            1143000,
            &para,
        ));
        next_id += 1;
    }

    if !body.is_empty() {
        let mut paras = String::new();
        for line in body.lines() {
            if line.is_empty() {
                paras.push_str(
                    r#"<a:p><a:pPr/><a:endParaRPr lang="zh-CN" sz="1800"/></a:p>"#,
                );
            } else {
                paras.push_str(&format!(
                    r#"<a:p>
            <a:pPr/>
            <a:r>
              <a:rPr lang="zh-CN" altLang="en-US" sz="1800" dirty="0">
                <a:latin typeface="Microsoft YaHei"/>
                <a:ea typeface="Microsoft YaHei"/>
              </a:rPr>
              <a:t>{}</a:t>
            </a:r>
            <a:endParaRPr lang="zh-CN" sz="1800"/>
          </a:p>"#,
                    xml_escape(line)
                ));
            }
        }
        shapes.push_str(&shape_box(
            next_id,
            "Content 2",
            457200,
            1600200,
            8229600,
            4525963,
            &paras,
        ));
    }

    // 空白页也放一个空文本框，避免个别阅读器拒绝空 spTree
    if shapes.is_empty() {
        shapes.push_str(&shape_box(
            2,
            "Content 1",
            457200,
            1600200,
            8229600,
            4525963,
            r#"<a:p><a:endParaRPr lang="zh-CN"/></a:p>"#,
        ));
    }

    format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name="Shape Tree"/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      {grp}
      {shapes}
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr>
    <a:masterClrMapping/>
  </p:clrMapOvr>
</p:sld>"#,
        grp = grp_sp_pr(),
        shapes = shapes
    )
}

fn theme_xml() -> &'static str {
    r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="NovaOffice">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
      <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
      <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
      <a:accent2><a:srgbClr val="C0504D"/></a:accent2>
      <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
      <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
      <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
      <a:accent6><a:srgbClr val="F79646"/></a:accent6>
      <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
      <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office">
      <a:majorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface="Microsoft YaHei"/>
        <a:cs typeface=""/>
      </a:majorFont>
      <a:minorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface="Microsoft YaHei"/>
        <a:cs typeface=""/>
      </a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Office">
      <a:fillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="1"/>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="100000"/><a:shade val="100000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="50000"/><a:shade val="100000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="0"/>
        </a:gradFill>
      </a:fillStyleLst>
      <a:lnStyleLst>
        <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill><a:prstDash val="solid"/></a:ln>
        <a:ln w="25400" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
        <a:ln w="38100" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
      </a:lnStyleLst>
      <a:effectStyleLst>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="57150" dist="19050" dir="5400000" algn="ctr" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
        </a:effectStyle>
      </a:effectStyleLst>
      <a:bgFillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="40000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="20000"/><a:satMod val="255000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:path path="circle"><a:fillToRect l="50000" t="-80000" r="50000" b="180000"/></a:path>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="80000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="30000"/><a:satMod val="200000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path>
        </a:gradFill>
      </a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
  <a:objectDefaults/>
  <a:extraClrSchemeLst/>
</a:theme>"#
}

/// 创建演示文稿。`slides` 为 (标题, 正文)；空切片则生成 1 张空白页。
pub fn create_pptx(path: &str, slides: &[(String, String)]) -> Result<()> {
    let path = Path::new(path);
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("无法创建目录：{}", parent.display()))?;
        }
    }

    let slides: Vec<(String, String)> = if slides.is_empty() {
        vec![(String::new(), String::new())]
    } else {
        slides.to_vec()
    };

    let file = File::create(path).with_context(|| format!("无法创建文件：{}", path.display()))?;
    let mut zip = ZipWriter::new(file);

    let mut content_types = String::from(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
"#,
    );
    for i in 1..=slides.len() {
        content_types.push_str(&format!(
            r#"  <Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
"#
        ));
    }
    content_types.push_str("</Types>");
    write_entry(&mut zip, "[Content_Types].xml", &content_types)?;

    write_entry(
        &mut zip,
        "_rels/.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>"#,
    )?;

    // rId1 = slideMaster, rId2 = theme, rId3… = slides（符合常见 Office 布局）
    let mut sld_id_lst = String::new();
    let mut pres_rels = String::from(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
"#,
    );
    for (i, _) in slides.iter().enumerate() {
        let n = i + 1;
        let rid = n + 2; // rId3 起
        let id = 255 + n as u32;
        sld_id_lst.push_str(&format!(
            r#"    <p:sldId id="{id}" r:id="rId{rid}"/>
"#
        ));
        pres_rels.push_str(&format!(
            r#"  <Relationship Id="rId{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{n}.xml"/>
"#
        ));
    }
    pres_rels.push_str("</Relationships>");

    // WPS / PowerPoint 都要求有 sldMasterIdLst
    let presentation = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" saveSubsetFonts="1">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId1"/>
  </p:sldMasterIdLst>
  <p:sldIdLst>
{sld_id_lst}  </p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>"#
    );
    write_entry(&mut zip, "ppt/presentation.xml", &presentation)?;
    write_entry(&mut zip, "ppt/_rels/presentation.xml.rels", &pres_rels)?;

    for (i, (title, body)) in slides.iter().enumerate() {
        let n = i + 1;
        write_entry(
            &mut zip,
            &format!("ppt/slides/slide{n}.xml"),
            &slide_xml(title, body),
        )?;
        write_entry(
            &mut zip,
            &format!("ppt/slides/_rels/slide{n}.xml.rels"),
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>"#,
        )?;
    }

    let layout = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
  <p:cSld name="Blank">
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name="Shape Tree"/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      {grp}
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>"#,
        grp = grp_sp_pr()
    );
    write_entry(&mut zip, "ppt/slideLayouts/slideLayout1.xml", &layout)?;
    write_entry(
        &mut zip,
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>"#,
    )?;

    let master = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg>
      <p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef>
    </p:bg>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name="Shape Tree"/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      {grp}
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>"#,
        grp = grp_sp_pr()
    );
    write_entry(&mut zip, "ppt/slideMasters/slideMaster1.xml", &master)?;
    write_entry(
        &mut zip,
        "ppt/slideMasters/_rels/slideMaster1.xml.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>"#,
    )?;
    write_entry(&mut zip, "ppt/theme/theme1.xml", theme_xml())?;

    write_entry(
        &mut zip,
        "docProps/core.xml",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Nova Build Presentation</dc:title>
  <dc:creator>Nova Build</dc:creator>
  <cp:lastModifiedBy>Nova Build</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:modified>
</cp:coreProperties>"#,
    )?;
    write_entry(
        &mut zip,
        "docProps/app.xml",
        &format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <TotalTime>0</TotalTime>
  <Words>0</Words>
  <Application>Nova Build</Application>
  <PresentationFormat>Widescreen</PresentationFormat>
  <Paragraphs>0</Paragraphs>
  <Slides>{}</Slides>
  <Notes>0</Notes>
  <HiddenSlides>0</HiddenSlides>
  <MMClips>0</MMClips>
  <ScaleCrop>false</ScaleCrop>
  <Company></Company>
  <LinksUpToDate>false</LinksUpToDate>
  <SharedDoc>false</SharedDoc>
  <HyperlinksChanged>false</HyperlinksChanged>
  <AppVersion>16.0000</AppVersion>
</Properties>"#,
            slides.len()
        ),
    )?;

    zip.finish().context("无法完成 pptx 打包")?;
    Ok(())
}

pub fn create_blank_pptx(path: &str) -> Result<()> {
    create_pptx(path, &[])
}

/// 从 pptx 抽取幻灯片文本（简易）。
pub fn extract_pptx_text(path: &str) -> Result<String> {
    let bytes = std::fs::read(path).with_context(|| format!("无法读取：{path}"))?;
    let mut archive = ZipArchive::new(Cursor::new(bytes)).context("invalid pptx")?;
    let mut out = Vec::new();
    let names: Vec<String> = (0..archive.len())
        .filter_map(|i| archive.by_index(i).ok().map(|f| f.name().to_string()))
        .filter(|n| n.starts_with("ppt/slides/slide") && n.ends_with(".xml"))
        .collect();
    let mut names = names;
    names.sort();
    for (idx, name) in names.iter().enumerate() {
        let mut file = archive.by_name(name)?;
        let mut xml = String::new();
        file.read_to_string(&mut xml)?;
        let text = strip_xml_to_text(&xml);
        out.push(format!("--- slide {} ---\n{text}", idx + 1));
    }
    Ok(out.join("\n\n"))
}

fn strip_xml_to_text(xml: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    let mut last_space = true;
    for ch in xml.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => {
                in_tag = false;
            }
            _ if in_tag => {}
            c if c.is_whitespace() => {
                if !last_space {
                    out.push(' ');
                    last_space = true;
                }
            }
            c => {
                out.push(c);
                last_space = false;
            }
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// CLI：`--create-blank-pptx <path>`
pub fn run_create_blank_pptx(argv: Vec<String>) -> i32 {
    let Some(path) = argv.first() else {
        eprintln!("usage: nova-desktop --create-blank-pptx <path.pptx>");
        return 2;
    };
    match create_blank_pptx(path) {
        Ok(()) => {
            println!("created {path}");
            0
        }
        Err(err) => {
            eprintln!("create-blank-pptx failed: {err:#}");
            1
        }
    }
}

/// CLI：`--create-pptx-json <slides.json> <out.pptx>`
/// JSON: `[{"title":"...","body":"..."}, ...]`
pub fn run_create_pptx_json(argv: Vec<String>) -> i32 {
    if argv.len() < 2 {
        eprintln!("usage: nova-desktop --create-pptx-json <slides.json> <out.pptx>");
        return 2;
    }
    let json_path = &argv[0];
    let out_path = &argv[1];
    let raw = match std::fs::read_to_string(json_path) {
        Ok(s) => s,
        Err(err) => {
            eprintln!("read json failed: {err}");
            return 1;
        }
    };
    let value: serde_json::Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(err) => {
            eprintln!("parse json failed: {err}");
            return 1;
        }
    };
    let Some(arr) = value.as_array() else {
        eprintln!("json root must be an array");
        return 2;
    };
    let slides: Vec<(String, String)> = arr
        .iter()
        .map(|s| {
            (
                s.get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
                s.get("body")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
            )
        })
        .collect();
    match create_pptx(out_path, &slides) {
        Ok(()) => {
            println!("created {out_path} with {} slide(s)", slides.len().max(1));
            0
        }
        Err(err) => {
            eprintln!("create-pptx-json failed: {err:#}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    #[test]
    fn pptx_contains_master_id_list() {
        let dir = std::env::temp_dir().join("nova-pptx-test");
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join("sample.pptx");
        create_pptx(
            path.to_str().unwrap(),
            &[
                ("封面".into(), "副标题\n第二行".into()),
                ("目录".into(), "1. 背景\n2. 方案".into()),
            ],
        )
        .unwrap();

        let bytes = std::fs::read(&path).unwrap();
        let mut archive = ZipArchive::new(Cursor::new(bytes)).unwrap();
        let mut pres = String::new();
        archive
            .by_name("ppt/presentation.xml")
            .unwrap()
            .read_to_string(&mut pres)
            .unwrap();
        assert!(
            pres.contains("sldMasterIdLst"),
            "presentation missing sldMasterIdLst: {pres}"
        );
        assert!(pres.contains(r#"r:id="rId1""#));
        let mut slide = String::new();
        archive
            .by_name("ppt/slides/slide1.xml")
            .unwrap()
            .read_to_string(&mut slide)
            .unwrap();
        assert!(slide.contains("prstGeom"));
        assert!(slide.contains("封面"));
    }
}
