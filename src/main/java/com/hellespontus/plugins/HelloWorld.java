package com.hellespontus.plugins;

import org.bukkit.plugin.java.JavaPlugin;

import java.util.logging.Logger;

public class HelloWorld extends JavaPlugin{
    Logger log = Logger.getLogger("Minecraft");

    public void onEnable(){
        log.info("Your plugin has been enabled!");
    }

    public void onDisable(){
        log.info("Your plugin has been disabled.");
    }
}
