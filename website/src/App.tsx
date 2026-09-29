import { useState } from 'react';

const asset = (name: string) => '/assets/' + name;
const downloadUrl = '/downloads/Glissform-0.1.0-beta.1.dmg';

function Brand() {
  return <span className="brand"><img src={asset('glissform-icon.png')} width="32" height="32" alt="" /><span>Glissform</span></span>;
}

function DownloadLink({ secondary = false }: { secondary?: boolean }) {
  return <a className={secondary ? 'download-link download-link--secondary' : 'download-link'} href={downloadUrl}>
    {secondary && <img src={asset('download.svg')} width="24" height="24" alt="" />}
    <span>{secondary ? 'Download for Mac' : 'Download Glissform'}</span>
  </a>;
}

function SectionIntro({ title, copy }: { title: [string, string]; copy: [string, string] }) {
  return <div className="section-intro">
    <h2>{title[0]}<br />{title[1]}</h2>
    <p>{copy[0]}<br />{copy[1]}</p>
  </div>;
}

function IllustrationSwitch() {
  return <span className="illustration-switch" aria-hidden="true"><span /></span>;
}

function SettingRow({ label, value, switchOn = false }: { label: string; value?: string; switchOn?: boolean }) {
  return <div className="setting-row"><span>{label}</span>{switchOn ? <IllustrationSwitch /> : <strong>{value}</strong>}</div>;
}

function FeatureShowcase() {
  const [selected, setSelected] = useState<'seamless' | 'battery'>('seamless');
  return <div className="feature-showcase" aria-label="Feature previews">
    <div className="feature-selector">
      <article className={'feature-option' + (selected === 'seamless' ? ' feature-option--selected' : '')}>
        <div className="feature-option__copy">
          <div className="feature-option__title">
            <span className="feature-icon feature-icon--seamless"><img src={asset('seamless-close.svg')} width="24" height="24" alt="" /></span>
            <h2>Seamless Close</h2>
          </div>
          <p>A little magic when you close your MacBook. Perspective and blur</p>
        </div>
        <button className="preview-button" type="button" aria-pressed={selected === 'seamless'} aria-controls="feature-preview" onClick={() => setSelected('seamless')}>
          <span className="preview-button__icon"><img src={asset('play.svg')} width="20" height="20" alt="" /></span><span>Try it</span>
        </button>
      </article>
      <article className={'feature-option' + (selected === 'battery' ? ' feature-option--selected' : '')}>
        <div className="feature-option__copy">
          <div className="feature-option__title">
            <span className="feature-icon feature-icon--battery"><img src={asset('battery-ripple.svg')} width="24" height="24" alt="" /></span>
            <h2>Battery Ripple</h2>
          </div>
          <p>Green when power connects.<br />Red when your battery reaches 20%.</p>
        </div>
        <button className="preview-button" type="button" aria-pressed={selected === 'battery'} aria-controls="feature-preview" onClick={() => setSelected('battery')}>
          <span className="preview-button__icon"><img src={asset('play.svg')} width="20" height="20" alt="" /></span><span>Try it</span>
        </button>
      </article>
    </div>
    <div className="feature-preview" id="feature-preview" aria-live="polite">
      {selected === 'seamless' ? <div className="feature-preview__screen"><img src={asset('seamless-settings.png')} alt="Still preview of Seamless Close settings in Glissform" /></div>
        : <div className="feature-preview__screen feature-preview__screen--battery"><img src={asset('battery-settings.png')} alt="Still preview of Battery Ripple settings in Glissform" /></div>}
      <div className="feature-preview__fade" aria-hidden="true" />
    </div>
  </div>;
}

const conveniences = [
  { icon: 'login.svg', title: 'Ready when you are', copy: 'Open Glissform when you sign in. Your preferences remain saved every time.' },
  { icon: 'menubar.svg', title: 'A click away', copy: 'Access settings and feature controls directly from your menu bar.' },
  { icon: 'background.svg', title: 'In the background', copy: 'Close the app but keep effects active. Decide if you want to run it.' },
  { icon: 'updates.svg', title: 'Updates, your way', copy: 'Install automatically or tap the update button when a new release is ready.' },
];

const faq = [
  { question: 'Will it work on my MacBook?', answer: 'Glissform requires macOS 15 or later. Seamless Close also needs a compatible lid-angle sensor. Testing so far is on a MacBook Air M5 15-inch.' },
  { question: 'Why does it ask for screen access?', answer: 'Seamless Close uses a temporary screenshot to animate your desktop. It stays in memory and is never uploaded. Battery Ripple does not need screen access.' },
  { question: 'What can I customize?', answer: 'Adjust blur, starting angle, detection time and pause timing. Choose your battery alerts, preview their effects, and decide how Glissform runs and updates.' },
  { question: 'How do I get new versions?', answer: 'The app checks for releases. Enable Automatic updates for background downloads and installation on quit, or install from the in-app Update button.' },
];

function App() {
  return <>
    <div className="desktop-site">
      <header className="site-header shell"><Brand /><DownloadLink secondary /></header>
      <main>
        <section className="hero shell" aria-labelledby="hero-title">
          <div className="hero__content">
            <h1 id="hero-title">Beautifully Polished<br />Everyday Mac Moments</h1>
            <p>Subtle animations and thoughtful improvements<br />for the way you use your MacBook.</p>
            <DownloadLink />
          </div>
          <FeatureShowcase />
        </section>

        <section className="section section--personalization shell" aria-label="Personalization">
          <SectionIntro title={['Easy To Customise.', 'Make It Feel Like Yours']} copy={['Choose the look, the timing, and the moments you want to see.', 'Small adjustments that make each experience feel like yours.']} />
          <div className="customization-grid">
            <article className="content-card blur-card">
              <div className="card-copy"><h3>Just the right amount of blur.</h3><p>Choose Subtle, Regular or High. Or turn blur off entirely.</p></div>
              <div className="blur-choices" aria-label="Illustration of the three available blur strengths">
                <div className="blur-choice"><div className="blur-choice__image"><img src={asset('blur-high.png')} alt="High blur preview" /></div><span>High</span></div>
                <div className="blur-choice blur-choice--selected"><div className="blur-choice__image"><img src={asset('blur-regular.png')} alt="Regular blur preview" /></div><span>Regular</span></div>
                <div className="blur-choice"><div className="blur-choice__image"><img src={asset('blur-subtle.png')} alt="Subtle blur preview" /></div><span>Subtle</span></div>
              </div>
            </article>
            <article className="content-card angle-card">
              <div className="card-copy"><h3>Start at just<br />the right angle.</h3><p>Choose when Seamless Close begins, or use your current lid position.</p></div>
              <div className="angle-illustration" aria-label="Illustration of a starting angle set to 100 degrees">
                <div className="angle-illustration__value"><span>Begin at</span><strong>100°</strong></div>
                <div className="angle-illustration__track"><span /></div>
              </div>
            </article>
            <article className="content-card settings-card">
              <div className="card-copy"><h3>Finds your angle.<br />Automatically.</h3><p>Let a still lid set the starting point. Choose how long to wait.</p></div>
              <div className="settings-card__rows"><SettingRow label="Detect starting angle" switchOn /><SettingRow label="Wait time" value="1.0 s" /></div>
            </article>
            <article className="content-card settings-card">
              <div className="card-copy"><h3>Pause.<br />Your desktop returns.</h3><p>Hold the lid still to restore the desktop. Set the pause delay to suit you.</p></div>
              <div className="settings-card__rows"><SettingRow label="Pause to return" switchOn /><SettingRow label="Wait time" value="0.5 s" /></div>
            </article>
            <article className="content-card settings-card">
              <div className="card-copy"><h3>Your moments.<br />Your choice.</h3><p>Enable each battery alert separately. Preview either ripple in app.</p></div>
              <div className="settings-card__rows"><SettingRow label="Power connection" switchOn /><SettingRow label="Battery at 20%" switchOn /></div>
            </article>
          </div>
        </section>

        <section className="section section--conveniences shell" aria-label="Everyday controls">
          <SectionIntro title={['Feels At Home.', 'Stays Out Of Your Way']} copy={['Choose how Glissform starts, runs, and stays up to date.', 'Everyday controls, right where you need them.']} />
          <div className="conveniences-grid">
            {conveniences.map((item) => <article className="convenience" key={item.title}><img src={asset(item.icon)} width="32" height="32" alt="" /><h3>{item.title}</h3><p>{item.copy}</p></article>)}
          </div>
        </section>

        <section className="privacy-panel shell" aria-labelledby="privacy-title">
          <div className="privacy-panel__intro"><img src={asset('privacy-shield.svg')} width="34" height="40" alt="" /><h2 id="privacy-title">Your Screen<br />Stays Yours</h2><p>Personal moments deserve privacy. Glissform keeps your screen images on your Mac.</p></div>
          <div className="privacy-panel__facts">
            <div><h3>No continuous recording.</h3><p>One temporary screenshot powers each gesture.</p></div>
            <div><h3>No saved or shared screenshots.</h3><p>Screen images stay in memory. They are never saved or sent.</p></div>
            <div><h3>No analytics.</h3><p>The app connects to this site for update checks and downloads.</p></div>
          </div>
        </section>

        <section className="section section--future shell" aria-label="More to come">
          <SectionIntro title={['More To Come.', 'Already In The Making']} copy={['We’re working on new features for everyday Mac moments.', 'Thoughtful additions, with the same attention to detail.']} />
          <img className="future-field" src={asset('future-field.svg')} width="1128" height="282" alt="" />
        </section>

        <section className="section section--faq shell" aria-labelledby="faq-title">
          <div className="faq-intro"><h2 id="faq-title">Good To Know</h2><p>A few practical details before you try it.</p></div>
          <div className="faq-list">
            {faq.map((item) => <div className="faq-item" key={item.question}><h3>{item.question}</h3><p>{item.answer}</p></div>)}
            <div className="faq-item"><h3>Will macOS ask me to approve it?</h3><p>Open the DMG and drag Glissform to Applications. The beta is not Apple notarized yet. After a blocked first launch, open System Settings → Privacy &amp; Security and choose Open Anyway if you trust the download. <a href="https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac">Apple’s instructions</a> explain this step.</p></div>
          </div>
        </section>

        <section className="download-panel shell" aria-labelledby="download-title"><h2 id="download-title">Make Your Mac Feel More Yours</h2><p>Try Glissform for MacBook. Available now in public beta.</p><DownloadLink /></section>
      </main>
      <footer className="site-footer shell"><Brand /><span>© 2026 Glissform</span></footer>
    </div>
    <div className="small-screen"><Brand /><p>Glissform is a macOS app.<br />Please use a MacBook to view this website.</p></div>
  </>;
}

export default App;
